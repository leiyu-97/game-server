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
from typing import Optional

install_path = Path(os.environ.get("DSP_SERVER_DIR", "/data/server"))
state_path = install_path / ".installed-mods.json"
cache_dir = Path(os.environ.get("DSP_MOD_CACHE_DIR") or (install_path.parent / "mod-cache"))
cache_manifest_path = cache_dir / "manifest.json"
offline_mode = os.environ.get("DSP_MOD_OFFLINE", "0") == "1"
headers = {
    "accept": "application/json",
    "user-agent": "game-server-dsp",
}
skip_entries = {"README.md", "CHANGELOG.md", "icon.png", "manifest.json", "nebula.LICENSE"}
resolved_packages = set()
requested_versions = {}


def info(message: str):
    print(f"[INFO] {message}", flush=True)


def fetch_json(url: str):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response)


def download(url: str, target: Path, label: str):
    info(f"Downloading {label} ...")
    target.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"user-agent": headers["user-agent"]})
    with urllib.request.urlopen(req, timeout=120) as response, target.open("wb") as output:
        shutil.copyfileobj(response, output)
    info(f"Downloaded {label}.")


def remove_path(path: Path):
    if not path.exists():
        return
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()


def package_key(namespace: str, name: str):
    return f"{namespace}-{name}"


def dependency_key(namespace: str, name: str, version: str):
    return f"{namespace}-{name}-{version}"


def archive_name(namespace: str, name: str, version: str):
    return f"{namespace}-{name}-{version}.zip"


def archive_path(namespace: str, name: str, version: str):
    return cache_dir / archive_name(namespace, name, version)


def load_state():
    if not state_path.exists():
        return {"packages": {}}
    try:
        data = json.loads(state_path.read_text())
    except json.JSONDecodeError:
        return {"packages": {}}
    packages = data.get("packages")
    if not isinstance(packages, dict):
        return {"packages": {}}
    return {"packages": packages}


def save_state(state):
    tmp_path = state_path.with_suffix(".tmp")
    tmp_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    tmp_path.replace(state_path)


def get_record(state, namespace: str, name: str):
    return state["packages"].get(package_key(namespace, name))


def record_package(state, namespace: str, name: str, version: str, targets, dependencies):
    state["packages"][package_key(namespace, name)] = {
        "namespace": namespace,
        "name": name,
        "version": version,
        "targets": sorted(targets),
        "dependencies": list(dependencies),
    }
    save_state(state)


def targets_exist(targets):
    for target in targets:
        if not (install_path / target).exists():
            return False
    return True


def refresh_record_dependencies(state, namespace: str, name: str, record, dependencies):
    if dependencies and record.get("dependencies") != list(dependencies):
        record_package(
            state,
            namespace,
            name,
            record["version"],
            record.get("targets") or [],
            dependencies,
        )


def parse_dependency(dep: str):
    first = dep.find("-")
    last = dep.rfind("-")
    if first <= 0 or last <= first:
        raise ValueError(f"Unexpected dependency format: {dep}")
    return dep[:first], dep[first + 1:last], dep[last + 1:]


def parse_root_spec(spec: str):
    spec = spec.strip()
    if not spec:
        raise ValueError("Empty mod spec")
    version = None
    if "@" in spec:
        spec, version = spec.split("@", 1)
        version = version.strip()
    if "-" not in spec:
        raise ValueError(f"Unexpected mod spec format: {spec}")
    namespace, name = spec.split("-", 1)
    if not namespace or not name:
        raise ValueError(f"Unexpected mod spec format: {spec}")
    return namespace, name, version


def version_key(version: str):
    parts = []
    for piece in version.split("."):
        match = re.match(r"^(\d+)(.*)$", piece)
        if match:
            parts.append((int(match.group(1)), match.group(2)))
        else:
            parts.append((0, piece))
    return tuple(parts)


def pick_version(current: str, candidate: str):
    return current if version_key(current) >= version_key(candidate) else candidate


def read_manifest_dependencies_from_zip(archive: Path):
    with zipfile.ZipFile(archive) as zf:
        manifest = json.loads(zf.read("manifest.json").decode())
    return manifest.get("dependencies") or []


def load_cache_manifest():
    if not cache_manifest_path.exists():
        return {"roots": {}, "packages": {}, "extra": None}
    try:
        data = json.loads(cache_manifest_path.read_text())
    except json.JSONDecodeError:
        return {"roots": {}, "packages": {}, "extra": None}
    roots = data.get("roots")
    packages = data.get("packages")
    extra = data.get("extra")
    if not isinstance(roots, dict):
        roots = {}
    if not isinstance(packages, dict):
        packages = {}
    if not isinstance(extra, dict):
        extra = None
    return {"roots": roots, "packages": packages, "extra": extra}


cache_manifest = load_cache_manifest()


def save_cache_manifest():
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_manifest_path.write_text(json.dumps(cache_manifest, indent=2, sort_keys=True) + "\n")


def record_cache_root(namespace: str, name: str, version: str):
    cache_manifest["roots"][package_key(namespace, name)] = {
        "namespace": namespace,
        "name": name,
        "version": version,
        "file": archive_name(namespace, name, version),
    }


def record_cache_package(namespace: str, name: str, version: str, dependencies):
    cache_manifest["packages"][dependency_key(namespace, name, version)] = {
        "namespace": namespace,
        "name": name,
        "version": version,
        "file": archive_name(namespace, name, version),
        "dependencies": list(dependencies),
    }


def manifest_package_entry(namespace: str, name: str, version: str):
    return cache_manifest["packages"].get(dependency_key(namespace, name, version))


def manifest_dependencies(namespace: str, name: str, version: str):
    entry = manifest_package_entry(namespace, name, version)
    if not entry:
        return None
    dependencies = entry.get("dependencies")
    return dependencies if isinstance(dependencies, list) else None


def highest_cached_archive(namespace: str, name: str):
    prefix = f"{namespace}-{name}-"
    best_version = None
    best_archive = None
    for archive in cache_dir.glob(f"{namespace}-{name}-*.zip"):
        if not archive.name.startswith(prefix):
            continue
        version = archive.name[len(prefix):-4]
        if best_version is None or version_key(version) > version_key(best_version):
            best_version = version
            best_archive = archive
    return best_version, best_archive


def acquire_archive(namespace: str, name: str, version: str, label: str):
    archive = archive_path(namespace, name, version)
    if archive.exists():
        return archive
    if offline_mode:
        raise SystemExit(
            f"Missing cached archive {archive.name} in {cache_dir} while DSP_MOD_OFFLINE=1"
        )
    download(
        f"https://thunderstore.io/package/download/{namespace}/{name}/{version}/",
        archive,
        label,
    )
    return archive


def resolve_package_version(namespace: str, name: str):
    if offline_mode:
        root_entry = cache_manifest["roots"].get(package_key(namespace, name))
        if root_entry:
            version = root_entry["version"]
            dependencies = manifest_dependencies(namespace, name, version)
            if dependencies is None:
                dependencies = read_manifest_dependencies_from_zip(archive_path(namespace, name, version))
            return version, dependencies
        version, archive = highest_cached_archive(namespace, name)
        if archive is None:
            raise SystemExit(
                f"No cached archive found for {namespace}/{name} in {cache_dir}; "
                "run ./servers/dsp/build-mods.sh first or pin DSP_MODS to a cached version"
            )
        dependencies = manifest_dependencies(namespace, name, version)
        if dependencies is None and not (namespace == "xiaoye97" and name == "BepInEx"):
            dependencies = read_manifest_dependencies_from_zip(archive)
        return version, dependencies or []
    meta = fetch_json(f"https://thunderstore.io/api/experimental/package/{namespace}/{name}/")
    latest = meta["latest"]
    return latest["version_number"], latest.get("dependencies") or []


def select_version(namespace: str, name: str, version: str):
    key = package_key(namespace, name)
    requested_version = requested_versions.get(key)
    selected_version = version
    if requested_version and requested_version != version:
        selected_version = pick_version(requested_version, version)
        info(
            f"Package {key} requested with versions {requested_version} and {version}; "
            f"using {selected_version}."
        )
    requested_versions[key] = selected_version
    return key, selected_version


def resolve_cached_package_version(namespace: str, name: str, minimum_version: Optional[str] = None):
    version, archive = highest_cached_archive(namespace, name)
    if archive is None:
        raise SystemExit(
            f"No cached archive found for {namespace}/{name} in {cache_dir}; "
            "run ./servers/dsp/build-mods.sh first or pin DSP_MODS to a cached version"
        )
    if minimum_version and version_key(version) < version_key(minimum_version):
        raise SystemExit(
            f"No cached archive found for {namespace}/{name} with version >= {minimum_version} in {cache_dir}; "
            "run ./servers/dsp/build-mods.sh first"
        )
    dependencies = manifest_dependencies(namespace, name, version)
    if dependencies is None and not (namespace == "xiaoye97" and name == "BepInEx"):
        dependencies = read_manifest_dependencies_from_zip(archive)
    return version, dependencies or []


def resolve_dependency_to_latest(namespace: str, name: str, version: str, prefer_latest: bool):
    if not prefer_latest:
        return version, None
    if offline_mode:
        latest_version, latest_dependencies = resolve_cached_package_version(
            namespace,
            name,
            minimum_version=version,
        )
    else:
        latest_version, latest_dependencies = resolve_package_version(namespace, name)
    if latest_version != version:
        info(
            f"Dependency {package_key(namespace, name)} declared as {version}; "
            f"using latest {latest_version}."
        )
    return latest_version, latest_dependencies


def normalize_dependencies(dependencies):
    normalized = []
    for dep in dependencies or []:
        namespace, name, version = parse_dependency(dep)
        selected_version = requested_versions.get(package_key(namespace, name)) or version
        normalized.append(dependency_key(namespace, name, selected_version))
    return normalized


def install_bepinex(state, version: str):
    namespace = "xiaoye97"
    name = "BepInEx"
    record = get_record(state, namespace, name)
    if record and record.get("version") == version and targets_exist(record.get("targets") or []):
        info(f"BepInEx {version} already exists, skipping download.")
        return

    archive = acquire_archive(namespace, name, version, f"BepInEx {version}")
    info(f"Extracting BepInEx {version} ...")
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(install_path)

    pack_root = install_path / "BepInExPack"
    targets = []
    if pack_root.exists():
        info("Moving BepInEx files into the game directory ...")
        for child in pack_root.iterdir():
            target = install_path / child.name
            targets.append(target.relative_to(install_path).as_posix())
            remove_path(target)
            shutil.move(str(child), str(target))
        shutil.rmtree(pack_root)

    for extra in ["icon.png", "manifest.json", "README.md", "changelog.txt"]:
        remove_path(install_path / extra)

    record_package(state, namespace, name, version, targets, [])
    info(f"BepInEx {version} is ready.")


def install_plugin_package(state, namespace: str, name: str, version: str, dependencies_hint=None):
    record = get_record(state, namespace, name)
    if record and record.get("version") == version and targets_exist(record.get("targets") or []):
        info(f"Plugin package {namespace}/{name} {version} already exists, skipping download.")
        dependencies = dependencies_hint or record.get("dependencies") or []
        refresh_record_dependencies(state, namespace, name, record, dependencies)
        for dep in dependencies:
            install_dependency(state, dep)
        return

    info(f"Installing plugin package {namespace}/{name} {version} ...")
    archive = acquire_archive(
        namespace,
        name,
        version,
        f"plugin package {namespace}/{name} {version}",
    )
    with zipfile.ZipFile(archive) as zf:
        dependencies = dependencies_hint or manifest_dependencies(namespace, name, version)
        if dependencies is None:
            manifest = json.loads(zf.read("manifest.json").decode())
            dependencies = manifest.get("dependencies") or []
        if dependencies:
            info(f"Resolving dependencies for {namespace}/{name} {version} ...")
            for dep in dependencies:
                install_dependency(state, dep)
            dependencies = normalize_dependencies(dependencies)
        info(f"Extracting plugin files for {namespace}/{name} {version} ...")
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            zf.extractall(tmp_dir)
            plugins_dir = install_path / "BepInEx/plugins"
            plugins_dir.mkdir(parents=True, exist_ok=True)
            targets = []
            for child in tmp_dir.iterdir():
                if child.name in skip_entries:
                    continue
                target = plugins_dir / child.name
                targets.append(target.relative_to(install_path).as_posix())
                remove_path(target)
                shutil.move(str(child), str(target))
    record_package(state, namespace, name, version, targets, dependencies)
    info(f"Plugin package {namespace}/{name} {version} is ready.")


def install_dependency(state, dep: str, dependencies_hint=None, prefer_latest: bool = True):
    namespace, name, version = parse_dependency(dep)
    resolved_version, latest_dependencies = resolve_dependency_to_latest(namespace, name, version, prefer_latest)
    key, selected_version = select_version(namespace, name, resolved_version)
    selected_dependencies = dependencies_hint
    if latest_dependencies is not None:
        selected_dependencies = latest_dependencies
    if selected_dependencies is None:
        selected_dependencies = manifest_dependencies(namespace, name, selected_version)

    resolved_key = f"{key}-{selected_version}"
    if resolved_key in resolved_packages:
        return
    resolved_packages.add(resolved_key)

    if namespace == "xiaoye97" and name == "BepInEx":
        install_bepinex(state, selected_version)
        return
    install_plugin_package(state, namespace, name, selected_version, selected_dependencies)


def build_dependency(dep: str, dependencies_hint=None, prefer_latest: bool = True):
    namespace, name, version = parse_dependency(dep)
    resolved_version, latest_dependencies = resolve_dependency_to_latest(namespace, name, version, prefer_latest)
    key, selected_version = select_version(namespace, name, resolved_version)

    resolved_key = f"{key}-{selected_version}"
    if resolved_key in resolved_packages:
        return
    resolved_packages.add(resolved_key)

    archive = acquire_archive(
        namespace,
        name,
        selected_version,
        f"package {namespace}/{name} {selected_version}",
    )

    dependencies = dependencies_hint
    if latest_dependencies is not None:
        dependencies = latest_dependencies
    if dependencies is None:
        dependencies = manifest_dependencies(namespace, name, selected_version)
    if dependencies is None and not (namespace == "xiaoye97" and name == "BepInEx"):
        dependencies = read_manifest_dependencies_from_zip(archive)
    if dependencies is None:
        dependencies = []

    for child_dep in dependencies:
        build_dependency(child_dep)
    dependencies = normalize_dependencies(dependencies)
    record_cache_package(namespace, name, selected_version, dependencies)


def root_specs_from_env():
    raw = os.environ.get("DSP_MODS", "nebula-NebulaMultiplayerMod")
    specs = []
    for piece in raw.replace(",", "\n").splitlines():
        spec = piece.strip()
        if not spec or spec.startswith("#"):
            continue
        specs.append(spec)
    if not specs:
        raise SystemExit("DSP_MODS did not contain any valid mod specs")
    return specs


def for_each_root(callback):
    specs = root_specs_from_env()
    for spec in specs:
        namespace, name, version = parse_root_spec(spec)
        if version:
            info(f"Using pinned mod {namespace}/{name} {version}.")
            callback(namespace, name, version, None)
            continue
        info(f"Resolving latest {namespace}/{name} version ...")
        resolved_version, dependencies = resolve_package_version(namespace, name)
        info(f"Using {namespace}/{name} {resolved_version}.")
        callback(namespace, name, resolved_version, dependencies)


def bootstrap_mods():
    state = load_state()

    def install_root(namespace, name, version, dependencies):
        install_dependency(
            state,
            dependency_key(namespace, name, version),
            dependencies,
            prefer_latest=False,
        )

    for_each_root(install_root)
    info(f"Installed mod versions recorded at {state_path}.")
    info("Mod bootstrap finished.")


def build_mods():
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_manifest["roots"] = {}
    cache_manifest["packages"] = {}
    cache_manifest["extra"] = None

    def build_root(namespace, name, version, dependencies):
        record_cache_root(namespace, name, version)
        build_dependency(
            dependency_key(namespace, name, version),
            dependencies,
            prefer_latest=False,
        )

    for_each_root(build_root)
    save_cache_manifest()
    info(f"Cached mod archives are ready in {cache_dir}.")
    info(f"Cache manifest written to {cache_manifest_path}.")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "mods"
    if command == "mods":
        bootstrap_mods()
        return
    if command == "build":
        build_mods()
        return
    raise SystemExit(f"Unsupported bootstrap command: {command}")


if __name__ == "__main__":
    main()
