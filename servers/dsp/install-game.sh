#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$ROOT_DIR/../.." && pwd)
DATA_ROOT="$ROOT_DIR/data"
SERVER_DIR="$DATA_ROOT/server"
WINE_DIR="$DATA_ROOT/wine"
LOG_DIR="$DATA_ROOT/logs"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$REPO_ROOT/.env"
  set +a
fi

IMPORT_DIR="${IMPORT_DIR:-$DATA_ROOT/import}"
EXTRA_DIR="${EXTRA_DIR:-$DATA_ROOT/goldgoldgold}"
DSP_MOD_CACHE_DIR="${DSP_MOD_CACHE_DIR:-$ROOT_DIR/data/mod-cache}"
STEAM_APP_ID="${STEAM_APP_ID:-1366540}"
EXTRA_ZIP_URL="${EXTRA_ZIP_URL:-https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/jobs/4247811310/artifacts/download}"
EXTRA_FORCE="${EXTRA_FORCE:-0}"
FORCE_UPDATE="${FORCE_UPDATE:-1}"
SAVE_IMPORT="${SAVE_IMPORT:-}"
SAVE_IMPORT_FORCE="${SAVE_IMPORT_FORCE:-0}"
STEAM_USER="${STEAM_USER:-}"
STEAM_PASS="${STEAM_PASS:-}"

log() { echo "[$(date -Iseconds)] $*"; }
warn() { echo "[WARN] $*" >&2; }
fail() { echo "[ERROR] $1" >&2; exit "${2:-1}"; }
require_file() { [[ -f "$1" ]] || fail "$2"; }

have_files() {
  local path
  for path in "$@"; do
    [[ -f "$path" ]] || return 1
  done
}

manifest_extra_archive() {
  local manifest_path="$DSP_MOD_CACHE_DIR/manifest.json"
  if [[ ! -f "$manifest_path" ]]; then
    return
  fi

  MANIFEST_PATH="$manifest_path" CACHE_DIR="$DSP_MOD_CACHE_DIR" python3 - <<'PY'
import json
import os
from pathlib import Path

manifest_path = Path(os.environ["MANIFEST_PATH"])
cache_dir = Path(os.environ["CACHE_DIR"])
try:
    data = json.loads(manifest_path.read_text())
except json.JSONDecodeError:
    raise SystemExit(0)
entry = data.get("extra")
if not isinstance(entry, dict):
    raise SystemExit(0)
file_name = entry.get("file")
if not isinstance(file_name, str) or not file_name:
    raise SystemExit(0)
archive = (cache_dir / file_name).resolve()
try:
    archive.relative_to(cache_dir.resolve())
except ValueError:
    raise SystemExit(0)
if archive.is_file():
    print(archive)
PY
}

docker_tty_args=()
if [[ -t 0 && -t 1 ]]; then
  docker_tty_args=(-it)
fi

if ! command -v docker >/dev/null 2>&1; then
  fail "docker is required on the host."
fi

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 is required on the host."
fi

docker_platform_args=()
if [[ -n "${DOCKER_PLATFORM:-}" ]]; then
  docker_platform_args=(--platform "$DOCKER_PLATFORM")
else
  docker_server_platform=$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}' 2>/dev/null || true)
  if [[ -n "$docker_server_platform" && "$docker_server_platform" != "<no value>/<no value>" ]]; then
    docker_platform_args=(--platform "$docker_server_platform")
  fi
fi

if [[ -z "$STEAM_USER" ]]; then
  fail "STEAM_USER is required. Set it in $REPO_ROOT/.env or export it before running install-game.sh."
fi

if [[ -z "$STEAM_PASS" && ${#docker_tty_args[@]} -eq 0 ]]; then
  fail "STEAM_PASS is not set and no interactive TTY is available for Steam login."
fi

mkdir -p "$SERVER_DIR" "$WINE_DIR" "$LOG_DIR" "$IMPORT_DIR" "$EXTRA_DIR"

steam_login_args=(+login "$STEAM_USER")
if [[ -n "$STEAM_PASS" ]]; then
  steam_login_args=(+login "$STEAM_USER" "$STEAM_PASS")
else
  cat <<EOF
[INFO] SteamCMD will start in a temporary container and log in as ${STEAM_USER}.
[INFO] Complete the interactive password / Steam Guard prompts if requested.
EOF
fi

if [[ "$FORCE_UPDATE" == "1" ]]; then
  log "Updating DSP via SteamCMD ..."
  docker run --rm "${docker_tty_args[@]}" "${docker_platform_args[@]}" \
    -v "$SERVER_DIR:/mnt/server" \
    steamcmd/steamcmd:ubuntu-24 \
    /usr/games/steamcmd \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir /mnt/server \
    "${steam_login_args[@]}" \
    +app_update "$STEAM_APP_ID" validate \
    +quit
else
  log "Skipping SteamCMD update because FORCE_UPDATE=$FORCE_UPDATE"
fi

require_file "$SERVER_DIR/DSPGAME.exe" "DSP installation failed: $SERVER_DIR/DSPGAME.exe not found."

install_extra_zip_if_requested() {
  local bundled_archive=""
  bundled_archive=$(manifest_extra_archive || true)

  if [[ -z "$bundled_archive" && -z "$EXTRA_ZIP_URL" ]]; then
    return
  fi

  if [[ -n "$(ls -A "$EXTRA_DIR" 2>/dev/null)" && "$EXTRA_FORCE" != "1" ]]; then
    log "Extra archive already extracted -> skipping (set EXTRA_FORCE=1 to reinstall)"
  else
    rm -rf "$EXTRA_DIR"/*
    mkdir -p "$EXTRA_DIR"

    if [[ -n "$bundled_archive" ]]; then
      log "Extracting bundled extra archive from $bundled_archive"
      EXTRA_ARCHIVE="$bundled_archive" EXTRA_DIR="$EXTRA_DIR" python3 - <<'PY'
import os
import zipfile
from pathlib import Path

archive = Path(os.environ["EXTRA_ARCHIVE"])
extra_dir = Path(os.environ["EXTRA_DIR"])
with zipfile.ZipFile(archive) as zf:
    zf.extractall(extra_dir)
PY
    else
      log "Downloading extra archive ..."
      EXTRA_ZIP_URL="$EXTRA_ZIP_URL" EXTRA_DIR="$EXTRA_DIR" python3 - <<'PY'
import os
import shutil
import urllib.request
import zipfile
from pathlib import Path

url = os.environ["EXTRA_ZIP_URL"]
extra_dir = Path(os.environ["EXTRA_DIR"])
archive = extra_dir.parent / ".extra.zip"
extra_dir.mkdir(parents=True, exist_ok=True)
req = urllib.request.Request(url, headers={"user-agent": "game-server-dsp"})
with urllib.request.urlopen(req, timeout=120) as response, archive.open("wb") as output:
    shutil.copyfileobj(response, output)
with zipfile.ZipFile(archive) as zf:
    zf.extractall(extra_dir)
archive.unlink()
PY
    fi
  fi

  local steam_api64
  steam_api64=$(find "$EXTRA_DIR" -type f -name steam_api64.dll -print -quit)
  if [[ -z "$steam_api64" ]]; then
    if [[ -n "$bundled_archive" ]]; then
      warn "Bundled extra archive did not contain steam_api64.dll under $EXTRA_DIR"
    else
      warn "EXTRA_ZIP_URL was set but steam_api64.dll was not found in $EXTRA_DIR"
    fi
    return
  fi

  local override_dir="$SERVER_DIR/DSPGAME_Data/Plugins/x86_64"
  mkdir -p "$override_dir"
  cp "$steam_api64" "$override_dir/steam_api64.dll"
  log "Installed steam_api64.dll override from extra archive"
}

ensure_steam_sdk_libs() {
  local sdk32="$SERVER_DIR/.steam/sdk32/steamclient.so"
  local sdk64="$SERVER_DIR/.steam/sdk64/steamclient.so"
  if [[ -f "$sdk64" ]]; then
    if [[ -f "$sdk32" ]]; then
      log "Steam SDK libraries already present -> skipping"
    else
      log "Steam SDK 64-bit library already present -> skipping bootstrap for required runtime dependency"
    fi
    return
  fi

  log "Bootstrapping Steam SDK libraries from the SteamCMD image ..."
  docker run --rm "${docker_platform_args[@]}" \
    --entrypoint /bin/sh \
    -v "$SERVER_DIR:/mnt/server" \
    steamcmd/steamcmd:ubuntu-24 \
    -lc '
      set -eu
      mkdir -p /mnt/server/.steam/sdk32 /mnt/server/.steam/sdk64
      src64=$(find / -type f \( -path "*/linux64/steamclient.so" -o -path "*/sdk64/steamclient.so" \) 2>/dev/null | head -n 1)
      [ -n "$src64" ]
      cp "$src64" /mnt/server/.steam/sdk64/steamclient.so
      src32=$(find / -type f \( -path "*/linux32/steamclient.so" -o -path "*/sdk32/steamclient.so" \) 2>/dev/null | head -n 1 || true)
      if [ -n "$src32" ]; then
        cp "$src32" /mnt/server/.steam/sdk32/steamclient.so
      fi
    '

  if [[ -f "$sdk32" ]]; then
    log "Steam SDK 32-bit library copied to $sdk32"
  else
    warn "Steam SDK 32-bit library was not found in the SteamCMD image; continuing with sdk64 only"
  fi
}

import_save_if_requested() {
  if [[ -z "$SAVE_IMPORT" ]]; then
    return
  fi

  local src="$IMPORT_DIR/$SAVE_IMPORT"
  local dest_dir="$WINE_DIR/drive_c/users/root/Documents/Dyson Sphere Program/Save"
  local dest="$dest_dir/$SAVE_IMPORT"
  require_file "$src" "SAVE_IMPORT is set but file not found: $src"

  mkdir -p "$dest_dir"
  if [[ -f "$dest" && "$SAVE_IMPORT_FORCE" != "1" ]]; then
    log "Save already exists -> skipping import (set SAVE_IMPORT_FORCE=1 to overwrite): $dest"
  else
    cp -f "$src" "$dest"
    log "Imported save: $src -> $dest"
  fi

  log "If you want to start with this save, set DSP_LOAD='${SAVE_IMPORT%.*}' in servers/dsp/docker-compose.yml."
}

install_extra_zip_if_requested
ensure_steam_sdk_libs
import_save_if_requested

require_file "$SERVER_DIR/DSPGAME.exe" "DSP installation failed: $SERVER_DIR/DSPGAME.exe not found."
require_file "$SERVER_DIR/.steam/sdk64/steamclient.so" "Steam SDK installation failed: sdk64/steamclient.so not found in $SERVER_DIR/.steam."

log "Game bootstrap completed. Then run ./servers/dsp/install-mods.sh"
