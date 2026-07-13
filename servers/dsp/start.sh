#!/usr/bin/env bash

set -euo pipefail

readonly DATA_ROOT="/data"
readonly SERVER_DIR="$DATA_ROOT/server"
readonly WINE_DIR="$DATA_ROOT/wine"
readonly STEAM_DIR="$DATA_ROOT/steam"
readonly LOG_DIR="$DATA_ROOT/logs"
readonly DSP_EXE="$SERVER_DIR/DSPGAME.exe"
readonly APP_ID="1366540"

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*"; }
fail() { printf '[ERROR] %s\n' "$1" >&2; exit "${2:-1}"; }

require_env() {
  [[ -n "${!1:-}" ]] || fail "Environment variable $1 is required."
}

resolve_steamcmd() {
  local candidate
  for candidate in steamcmd /usr/games/steamcmd /home/steam/steamcmd/steamcmd.sh; do
    if [[ "$candidate" == /* ]]; then
      [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return; }
    elif command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return
    fi
  done
  fail "SteamCMD executable was not found in the container."
}

write_bepinex_config() {
  local config_dir="$SERVER_DIR/BepInEx/config"
  local config_file="$config_dir/BepInEx.cfg"

  mkdir -p "$config_dir"
  if [[ -f "$config_file" ]]; then
    log "BepInEx.cfg already exists; keeping the existing file"
    return
  fi

  cat >"$config_file" <<'EOF'
[Caching]
EnableAssemblyCache = true

[Logging]
UnityLogListening = true
LogConsoleToUnityLog = false

[Logging.Disk]
WriteUnityLog = true
AppendLog = false
Enabled = true

[Preloader]
ApplyRuntimePatches = true
HarmonyBackend = auto
EOF
  log "Created BepInEx configuration"
}

initialize_wine_prefix() {
  if [[ -f "$WINE_DIR/system.reg" ]]; then
    return
  fi

  log "Initializing Wine prefix"
  xvfb-run -a -s '-screen 0 1280x720x24 -ac +extension GLX +render -noreset' \
    wineboot -u >>"$LOG_DIR/console_headless.log" 2>&1
  wineserver -w >>"$LOG_DIR/console_headless.log" 2>&1 || true
  [[ -f "$WINE_DIR/system.reg" ]] || fail "Wine prefix initialization failed. Check $LOG_DIR/console_headless.log."
}

require_env STEAM_USER
require_env STEAM_PASS

export HOME="$STEAM_DIR"
export WINEPREFIX="$WINE_DIR"
export WINEDEBUG='-all'
export WINEDLLOVERRIDES='mscoree=n,b;mshtml=n,b;winhttp=n,b'
export LIBGL_ALWAYS_SOFTWARE=1

mkdir -p "$SERVER_DIR" "$WINE_DIR" "$STEAM_DIR" "$LOG_DIR"
touch "$LOG_DIR/console_headless.log" "$LOG_DIR/unity_headless.log"

if [[ ! -f "$DSP_EXE" ]]; then
  steamcmd_bin="$(resolve_steamcmd)"
  log "DSP is not installed; downloading app $APP_ID with SteamCMD"
  "$steamcmd_bin" \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "$SERVER_DIR" \
    +login "$STEAM_USER" "$STEAM_PASS" \
    +app_update "$APP_ID" validate \
    +quit
  [[ -f "$DSP_EXE" ]] || fail "SteamCMD completed but $DSP_EXE was not created."
else
  log "DSP game files already exist; skipping SteamCMD download"
fi

log "Reconciling BepInEx and Nebula packages from Thunderstore"
python3 /bootstrap.py mods

[[ -f "$SERVER_DIR/winhttp.dll" ]] || fail "BepInEx installation failed: winhttp.dll is missing."
[[ -f "$SERVER_DIR/BepInEx/plugins/NebulaAPI.dll" ]] || fail "Nebula API installation failed: NebulaAPI.dll is missing."
[[ -f "$SERVER_DIR/BepInEx/plugins/NebulaPatcher.dll" ]] || fail "Nebula installation failed: NebulaPatcher.dll is missing."

write_bepinex_config
initialize_wine_prefix

mkdir -p "$SERVER_DIR/BepInEx"
touch "$SERVER_DIR/BepInEx/LogOutput.log"

log "Starting DSP dedicated server on TCP port 8469"
exec xvfb-run -a -s '-screen 0 1280x720x24 -ac +extension GLX +render -noreset' \
  wine "$DSP_EXE" \
    --doorstop-enable true \
    --doorstop-target '.\\BepInEx\\core\\BepInEx.Preloader.dll' \
    -batchmode \
    -nographics \
    -nebula-server \
    -newgame-cfg \
    -logFile 'Z:\\data\\logs\\unity_headless.log' \
  >>"$LOG_DIR/console_headless.log" 2>&1
