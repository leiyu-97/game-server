#!/usr/bin/env bash

set -euo pipefail

log() { echo "[$(date -Iseconds)] $*"; }
warn() { echo "[WARN] $*" >&2; }
fail() { echo "[ERROR] $1" >&2; exit "${2:-1}"; }

DATA_ROOT="/data"
SERVER_DIR="$DATA_ROOT/server"
WINE_DIR="$DATA_ROOT/wine"
LOG_DIR="$DATA_ROOT/logs"
PLUGINS_DIR="$SERVER_DIR/BepInEx/plugins"
DSP_EXE="$SERVER_DIR/DSPGAME.exe"

require_plugin_file() {
  local file_name="$1"
  local message="$2"
  find "$PLUGINS_DIR" -type f -name "$file_name" -print -quit | grep -q . || fail "$message"
}

ensure_safe_wine_prefix() {
  [[ -n "$WINE_DIR" ]] || fail "WINE prefix path is empty." 11
  [[ "$WINE_DIR" != "/" ]] || fail "Refusing to use / as WINE prefix." 12
}

prefix_is_ready() {
  [[ -f "$WINE_DIR/system.reg" ]] && [[ -f "$WINE_DIR/drive_c/windows/system32/kernel32.dll" ]]
}

initialize_wine_prefix() {
  ensure_safe_wine_prefix
  log "Initializing Wine prefix at $WINE_DIR"
  mkdir -p "$WINE_DIR"
  wineboot -u >> "$LOG_DIR/console_headless.log" 2>&1 || fail "Wine prefix initialization failed at $WINE_DIR. Check $LOG_DIR/console_headless.log."
  wineserver -w >> "$LOG_DIR/console_headless.log" 2>&1 || true
  prefix_is_ready || fail "Wine prefix is incomplete after initialization at $WINE_DIR. Check $LOG_DIR/console_headless.log."
}

export HOME="/root"
export WINEPREFIX="$WINE_DIR"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="mscoree=n,b;mshtml=n,b;winhttp=n,b"
export LIBGL_ALWAYS_SOFTWARE=1

mkdir -p "$SERVER_DIR" "$WINE_DIR" "$LOG_DIR"
touch "$LOG_DIR/unity_headless.log" "$LOG_DIR/console_headless.log"

[[ -f "$DSP_EXE" ]] || fail "Server executable not found: $DSP_EXE. Run ./servers/dsp/install-game.sh first."
[[ -f "$SERVER_DIR/winhttp.dll" ]] || fail "BepInEx files not found in $SERVER_DIR. Run ./servers/dsp/install-mods.sh first."
require_plugin_file "NebulaAPI.dll" "Nebula API file not found under $PLUGINS_DIR. Run ./servers/dsp/install-mods.sh first."
require_plugin_file "NebulaPatcher.dll" "Nebula mod file not found under $PLUGINS_DIR. Run ./servers/dsp/install-mods.sh first."
if [[ ! -f "$SERVER_DIR/.steam/sdk32/steamclient.so" ]]; then
  warn "Steam SDK 32-bit library not found in $SERVER_DIR/.steam/sdk32; continuing with sdk64 only."
fi
[[ -f "$SERVER_DIR/.steam/sdk64/steamclient.so" ]] || fail "Steam SDK 64-bit library not found in $SERVER_DIR/.steam/sdk64. Run ./servers/dsp/install-game.sh first."

XVFB_DISPLAY="${XVFB_DISPLAY:-:99}"
XVFB_SCREEN="${XVFB_SCREEN:-1280x720x24}"

ONESHOT_RESTART="${ONESHOT_RESTART:-1}"
ONESHOT_TIMEOUT="${ONESHOT_TIMEOUT:-120}"
ONESHOT_LOG="${ONESHOT_LOG:-$SERVER_DIR/BepInEx/LogOutput.log}"
ONESHOT_PATTERN="${ONESHOT_PATTERN:-Listening server on port}"
ONESHOT_MARKER="${ONESHOT_MARKER:-$DATA_ROOT/.oneshot_restart_done}"

DSP_LOAD="${DSP_LOAD:-}"
DSP_LOAD_LATEST="${DSP_LOAD_LATEST:-0}"
DSP_NEWGAME_SEED="${DSP_NEWGAME_SEED:-}"
DSP_NEWGAME_STARCOUNT="${DSP_NEWGAME_STARCOUNT:-}"
DSP_NEWGAME_RESOURCE_MULT="${DSP_NEWGAME_RESOURCE_MULT:-}"
DSP_NEWGAME_CFG="${DSP_NEWGAME_CFG:-0}"
DSP_NEWGAME_DEFAULT="${DSP_NEWGAME_DEFAULT:-0}"
DSP_UPS="${DSP_UPS:-}"

ARGS=( -batchmode -hidewindow 1 -nebula-server )

if [[ -n "$DSP_UPS" ]]; then
  ARGS+=( -ups "$DSP_UPS" )
fi

if [[ -n "$DSP_LOAD" ]]; then
  ARGS+=( -load "$DSP_LOAD" )
elif [[ "$DSP_LOAD_LATEST" == "1" ]]; then
  ARGS+=( -load-latest )
elif [[ -n "$DSP_NEWGAME_SEED" || -n "$DSP_NEWGAME_STARCOUNT" || -n "$DSP_NEWGAME_RESOURCE_MULT" ]]; then
  if [[ -z "$DSP_NEWGAME_SEED" || -z "$DSP_NEWGAME_STARCOUNT" || -z "$DSP_NEWGAME_RESOURCE_MULT" ]]; then
    echo "ERROR: For -newgame you must set DSP_NEWGAME_SEED, DSP_NEWGAME_STARCOUNT, DSP_NEWGAME_RESOURCE_MULT" >&2
    exit 1
  fi
  ARGS+=( -newgame "$DSP_NEWGAME_SEED" "$DSP_NEWGAME_STARCOUNT" "$DSP_NEWGAME_RESOURCE_MULT" )
elif [[ "$DSP_NEWGAME_CFG" == "1" ]]; then
  ARGS+=( -newgame-cfg )
elif [[ "$DSP_NEWGAME_DEFAULT" == "1" ]]; then
  ARGS+=( -newgame-default )
else
  ARGS+=( -newgame-cfg )
fi

ARGS+=( -logFile "Z:\\data\\logs\\unity_headless.log" )

cd "$SERVER_DIR"

log "Launching DSPGAME.exe with args: ${ARGS[*]}"
log "Console log redirect -> $LOG_DIR/console_headless.log"

log "Cleanup: killing old wine/Xvfb (if any)"
pkill -9 -f 'DSPGAME.exe' >/dev/null 2>&1 || true
pkill -9 -f 'wine64' >/dev/null 2>&1 || true
pkill -9 -f 'wineserver' >/dev/null 2>&1 || true
pkill -9 -f 'Xvfb' >/dev/null 2>&1 || true

disp_num="${XVFB_DISPLAY#:}"
rm -f "/tmp/.X${disp_num}-lock" "/tmp/.X11-unix/X${disp_num}" >/dev/null 2>&1 || true

export DISPLAY="$XVFB_DISPLAY"
log "Starting Xvfb on DISPLAY=$DISPLAY ..."
Xvfb "$DISPLAY" -screen 0 "$XVFB_SCREEN" -ac +extension GLX +render -noreset \
  >> "$LOG_DIR/console_headless.log" 2>&1 &
XVFB_PID=$!

DSP_CHILD_PID=""

cleanup() {
  if [[ -n "$DSP_CHILD_PID" ]] && kill -0 "$DSP_CHILD_PID" >/dev/null 2>&1; then
    log "Stopping DSP process (pid=$DSP_CHILD_PID)"
    kill "$DSP_CHILD_PID" >/dev/null 2>&1 || true
  fi
  log "Stopping Xvfb (pid=$XVFB_PID)"
  kill "$XVFB_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 1

if ! prefix_is_ready; then
  initialize_wine_prefix
fi

mkdir -p "$(dirname "$ONESHOT_LOG")"
touch "$ONESHOT_LOG" >/dev/null 2>&1 || true

DSP_PID_FILE="$DATA_ROOT/.dsp_pid"
rm -f "$DSP_PID_FILE"

wine ./DSPGAME.exe "${ARGS[@]}" >> "$LOG_DIR/console_headless.log" 2>&1 &
WINE_PID=$!

for _ in $(seq 1 15); do
  DSP_CHILD_PID=$(pgrep -n -f 'DSPGAME\.exe' || true)
  if [[ -n "$DSP_CHILD_PID" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$DSP_CHILD_PID" ]]; then
  log "Could not find DSPGAME.exe process after launching wine. Falling back to wine pid=$WINE_PID"
  DSP_CHILD_PID="$WINE_PID"
else
  log "Tracking DSPGAME.exe process pid=$DSP_CHILD_PID (wine pid=$WINE_PID)"
fi

printf '%s\n' "$DSP_CHILD_PID" > "$DSP_PID_FILE"

if [[ "$ONESHOT_RESTART" == "1" && ! -f "$ONESHOT_MARKER" ]]; then
  log "One-shot restart watchdog enabled (timeout=${ONESHOT_TIMEOUT}s, pattern='$ONESHOT_PATTERN', log=$ONESHOT_LOG)"
  start_ts="$(date +%s)"

  while true; do
    if ! kill -0 "$DSP_CHILD_PID" >/dev/null 2>&1; then
      log "DSP exited before one-shot check completed. Marking oneshot done and exiting 1."
      echo "done" > "$ONESHOT_MARKER" || true
      wait "$WINE_PID" || true
      exit 1
    fi

    if grep -qF "$ONESHOT_PATTERN" "$ONESHOT_LOG" 2>/dev/null; then
      log "One-shot watchdog OK: pattern found. Marking oneshot done; continuing normally."
      echo "done" > "$ONESHOT_MARKER" || true
      break
    fi

    now_ts="$(date +%s)"
    elapsed=$((now_ts - start_ts))
    if (( elapsed >= ONESHOT_TIMEOUT )); then
      log "One-shot watchdog FAIL: pattern not found within ${ONESHOT_TIMEOUT}s."
      log "Triggering exactly one container restart (exit 42) and marking oneshot done."
      echo "done" > "$ONESHOT_MARKER" || true
      kill "$DSP_CHILD_PID" >/dev/null 2>&1 || true
      kill "$WINE_PID" >/dev/null 2>&1 || true
      sleep 2
      kill -9 "$DSP_CHILD_PID" >/dev/null 2>&1 || true
      kill -9 "$WINE_PID" >/dev/null 2>&1 || true
      exit 42
    fi

    sleep 2
  done
else
  if [[ "$ONESHOT_RESTART" != "1" ]]; then
    log "One-shot restart watchdog disabled (ONESHOT_RESTART=$ONESHOT_RESTART)"
  else
    log "One-shot restart already done (marker exists: $ONESHOT_MARKER) -> running normally"
  fi
fi

wait "$WINE_PID"
