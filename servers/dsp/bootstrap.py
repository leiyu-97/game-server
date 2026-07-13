#!/usr/bin/env python3

import json
import os
import re
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

INSTALL_PATH = Path(os.environ.get("DSP_SERVER_DIR", "/data/server"))
STATE_PATH = INSTALL_PATH / ".installed-mods.json"
CACHE_DIR = Path(os.environ.get("DSP_MOD_CACHE_DIR", "/data/mod-cache"))
HEADERS = {"accept": "application/json", "user-agent": "game-server-dsp"}
SKIP_ENTRIES = {"README.md", "CHANGELOG.md", "icon.png", "manifest.json", "nebula.LICENSE"}


def info(message):
    print(f"[INFO] {message}", flush=True)


def package_key(namespace, name):
    return f"{namespace}-{name}"


def package_label(namespace, name, version):
    return f"{namespace}/{name} {version}"


def parse_dependency(value):
    first = value.find("-")
    last = value.rfind("-")
    if first <= 0 or last <= first:
        raise ValueError(f"Unexpected dependency format: {value}")
    return value[:first], value[first + 1:last], value[last + 1:]


def version_key(version):
    result = []
    for piece in version.split("."):
        match = re.match(r"^(\d+)(.*)$", piece)
        result.append((int(match.group(1)), match.group(2)) if match else (0, piece))
    return tuple(result)


def load_state():
    if not STATE_PATH.exists():
        return {"packages": {}}
    try:
        state = json.loads(STATE_PATH.read_text())
    except json.JSONDecodeError:
        return {"packages": {}}
    return {"packages": state.get("packages", {})} if isinstance(state.get("packages"), dict) else {"packages": {}}


def save_state(state):
    temporary = STATE_PATH.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    temporary.replace(STATE_PATH)


def targets_exist(targets):
    return bool(targets) and all((INSTALL_PATH / target).exists() for target in targets)


def fetch_json(url):
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def archive_path(namespace, name, version):
    return CACHE_DIR / f"{namespace}-{name}-{version}.zip"


def acquire_archive(namespace, name, version):
    archive = archive_path(namespace, name, version)
    if archive.exists():
        info(f"Using cached package {package_label(namespace, name, version)}.")
        return archive

    label = package_label(namespace, name, version)
    info(f"Downloading package {label} ...")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        f"https://thunderstore.io/package/download/{namespace}/{name}/{version}/",
        headers={"user-agent": HEADERS["user-agent"]},
    )
    temporary = archive.with_suffix(".part")
    try:
        with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        temporary.replace(archive)
    finally:
        temporary.unlink(missing_ok=True)
    info(f"Downloaded package {label}.")
    return archive


def manifest_dependencies(archive):
    with zipfile.ZipFile(archive) as bundle:
        manifest = json.loads(bundle.read("manifest.json").decode())
    return manifest.get("dependencies") or []


def remove_path(path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()


def safe_extract(bundle, destination):
    destination = destination.resolve()
    for member in bundle.infolist():
        target = (destination / member.filename).resolve()
        if target != destination and destination not in target.parents:
            raise ValueError(f"Archive entry escapes destination: {member.filename}")
    bundle.extractall(destination)


def install_bepinex(state, namespace, name, version, archive):
    record = state["packages"].get(package_key(namespace, name))
    if record and record.get("version") == version and targets_exist(record.get("targets", [])):
        info(f"BepInEx {version} already exists, skipping extraction.")
        return

    info(f"Extracting BepInEx {version} ...")
    with zipfile.ZipFile(archive) as bundle:
        safe_extract(bundle, INSTALL_PATH)

    pack_root = INSTALL_PATH / "BepInExPack"
    if not pack_root.is_dir():
        raise RuntimeError("BepInEx package did not contain BepInExPack")

    targets = []
    for child in pack_root.iterdir():
        target = INSTALL_PATH / child.name
        remove_path(target)
        shutil.move(str(child), str(target))
        targets.append(target.relative_to(INSTALL_PATH).as_posix())
    shutil.rmtree(pack_root)

    for extra in ("icon.png", "manifest.json", "README.md", "changelog.txt"):
        remove_path(INSTALL_PATH / extra)

    state["packages"][package_key(namespace, name)] = {
        "namespace": namespace,
        "name": name,
        "version": version,
        "targets": sorted(targets),
        "dependencies": [],
    }
    info(f"BepInEx {version} is ready.")


def install_plugin(state, namespace, name, version, archive, install_dependency):
    record = state["packages"].get(package_key(namespace, name))
    if record and record.get("version") == version and targets_exist(record.get("targets", [])):
        info(f"Plugin package {package_label(namespace, name, version)} already exists, skipping extraction.")
        dependencies = record.get("dependencies", [])
    else:
        dependencies = manifest_dependencies(archive)

    if dependencies:
        info(f"Resolving dependencies for {package_label(namespace, name, version)} ...")
        for dependency in dependencies:
            install_dependency(dependency)

    if record and record.get("version") == version and targets_exist(record.get("targets", [])):
        return

    info(f"Extracting plugin files for {package_label(namespace, name, version)} ...")
    plugins_dir = INSTALL_PATH / "BepInEx/plugins"
    plugins_dir.mkdir(parents=True, exist_ok=True)
    targets = []
    with zipfile.ZipFile(archive) as bundle, tempfile.TemporaryDirectory() as temporary:
        temp_dir = Path(temporary)
        safe_extract(bundle, temp_dir)
        for child in temp_dir.iterdir():
            if child.name in SKIP_ENTRIES:
                continue
            target = plugins_dir / child.name
            remove_path(target)
            shutil.move(str(child), str(target))
            targets.append(target.relative_to(INSTALL_PATH).as_posix())

    state["packages"][package_key(namespace, name)] = {
        "namespace": namespace,
        "name": name,
        "version": version,
        "targets": sorted(targets),
        "dependencies": dependencies,
    }
    info(f"Plugin package {package_label(namespace, name, version)} is ready.")


def bootstrap_mods():
    INSTALL_PATH.mkdir(parents=True, exist_ok=True)
    state = load_state()
    selected_versions = {}
    processed = set()

    def install_dependency(value):
        namespace, name, requested_version = parse_dependency(value)
        key = package_key(namespace, name)
        previous = selected_versions.get(key)
        version = requested_version if previous is None else max(previous, requested_version, key=version_key)
        if previous and previous != requested_version:
            info(f"Package {key} requested with versions {previous} and {requested_version}; using {version}.")
        selected_versions[key] = version

        identity = f"{key}-{version}"
        if identity in processed:
            return
        processed.add(identity)

        archive = acquire_archive(namespace, name, version)
        if namespace == "xiaoye97" and name == "BepInEx":
            install_bepinex(state, namespace, name, version, archive)
        else:
            install_plugin(state, namespace, name, version, archive, install_dependency)

    info("Resolving latest nebula/NebulaMultiplayerMod version ...")
    metadata = fetch_json("https://thunderstore.io/api/experimental/package/nebula/NebulaMultiplayerMod/")
    latest = metadata["latest"]
    root_version = latest["version_number"]
    info(f"Using nebula/NebulaMultiplayerMod {root_version}.")
    install_dependency(f"nebula-NebulaMultiplayerMod-{root_version}")

    save_state(state)
    info(f"Installed mod versions recorded at {STATE_PATH}.")
    info("Mod bootstrap finished.")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "mods"
    if command != "mods":
        raise SystemExit(f"Unsupported bootstrap command: {command}")
    bootstrap_mods()


if __name__ == "__main__":
    main()
