#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$ROOT_DIR/../.." && pwd)

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$REPO_ROOT/.env"
  set +a
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERROR] python3 is required on the host." >&2
  exit 1
fi

DSP_MODS="${DSP_MODS:-nebula-NebulaMultiplayerMod}"
DSP_SERVER_DIR="${DSP_SERVER_DIR:-$ROOT_DIR/data/server}"
DSP_MOD_CACHE_DIR="${DSP_MOD_CACHE_DIR:-$ROOT_DIR/data/mod-cache}"
DSP_MOD_BUNDLE_PATH="${DSP_MOD_BUNDLE_PATH:-$ROOT_DIR/data/mod-cache.tar.gz}"
DSP_MOD_OFFLINE="${DSP_MOD_OFFLINE:-1}"

mkdir -p "$DSP_SERVER_DIR"

if [[ -f "$DSP_MOD_BUNDLE_PATH" ]]; then
  echo "[INFO] Extracting mod bundle from $DSP_MOD_BUNDLE_PATH"
  rm -rf "$DSP_MOD_CACHE_DIR"
  mkdir -p "$DSP_MOD_CACHE_DIR"
  tar -xzf "$DSP_MOD_BUNDLE_PATH" -C "$DSP_MOD_CACHE_DIR"
fi

if [[ "$DSP_MOD_OFFLINE" == "1" && ! -f "$DSP_MOD_CACHE_DIR/manifest.json" ]]; then
  echo "[ERROR] Offline mode requires $DSP_MOD_CACHE_DIR/manifest.json. Run ./servers/dsp/build-mods.sh first or provide DSP_MOD_BUNDLE_PATH." >&2
  exit 1
fi

write_bepinex_config() {
  local config_dir="$DSP_SERVER_DIR/BepInEx/config"
  local config_file="$config_dir/BepInEx.cfg"
  mkdir -p "$config_dir"

  if [[ -f "$config_file" ]]; then
    echo "[INFO] BepInEx.cfg already present -> keeping existing file"
    return
  fi

  cat > "$config_file" <<'EOF'
[Caching]
EnableAssemblyCache = true

[Chainloader]
HideManagerGameObject = false

[Harmony.Logger]
LogChannels = Warn, Error

[Logging]
UnityLogListening = true
LogConsoleToUnityLog = false

[Logging.Console]
Enabled = true
PreventClose = false
ShiftJisEncoding = false
StandardOutType = Auto
LogLevels = Fatal, Error, Warning, Message, Info

[Logging.Disk]
WriteUnityLog = true
AppendLog = false
Enabled = true
LogLevels = Fatal, Error, Warning, Message, Info

[Preloader]
ApplyRuntimePatches = true
HarmonyBackend = auto
DumpAssemblies = false
LoadDumpedAssemblies = false
BreakBeforeLoadAssemblies = false

[Preloader.Entrypoint]
Assembly = UnityEngine.CoreModule.dll
Type = Application
Method = .cctor
EOF
}

require_file() {
  [[ -f "$1" ]] || {
    echo "[ERROR] $2" >&2
    exit 1
  }
}

echo "[INFO] Reconciling DSP mods via bootstrap ..."
DSP_MODS="$DSP_MODS" \
DSP_SERVER_DIR="$DSP_SERVER_DIR" \
DSP_MOD_CACHE_DIR="$DSP_MOD_CACHE_DIR" \
DSP_MOD_OFFLINE="$DSP_MOD_OFFLINE" \
python3 "$ROOT_DIR/bootstrap.py" mods

write_bepinex_config

require_file "$DSP_SERVER_DIR/winhttp.dll" "BepInEx installation failed: winhttp.dll not found in $DSP_SERVER_DIR."
require_file "$DSP_SERVER_DIR/BepInEx/plugins/NebulaAPI.dll" "Nebula API installation failed: NebulaAPI.dll not found in $DSP_SERVER_DIR/BepInEx/plugins."
require_file "$DSP_SERVER_DIR/BepInEx/plugins/NebulaPatcher.dll" "Nebula installation failed: NebulaPatcher.dll not found in $DSP_SERVER_DIR/BepInEx/plugins."

echo "[INFO] Mod installation completed. Start the container with: ./game-server.sh -n dsp start"
