#! /bin/bash

# Set default values for environment variables
INSTALL_PATH="${INSTALL_PATH:-/desynced/server}"
SERVER_NAME="${SERVER_NAME:-DesyncedServer}"
WORLD_NAME="${WORLD_NAME:-World1}"
MAX_PLAYERS="${MAX_PLAYERS:-4}"
VISIBILITY="${VISIBILITY:-private}"
RUN_WITHOUT_PLAYERS="${RUN_WITHOUT_PLAYERS:-false}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
RESOURCE_AMT="${RESOURCE_AMT:-1}"
BLIGHT_THRESHOLD="${BLIGHT_THRESHOLD:-0.1}"
PLATEAU_LEVEL="${PLATEAU_LEVEL:-0.1}"
PEACEFUL_MODE="${PEACEFUL_MODE:-2}"
RESOURCE_INF="${RESOURCE_INF:-false}"

steamcmd \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir "$INSTALL_PATH" \
  +login anonymous \
  +app_update 2943070 validate \
  +quit

STEAM_EXIT=$?
if [[ $STEAM_EXIT -ne 0 ]]; then
  echo "ERROR: SteamCMD exited with code $STEAM_EXIT"
  exit 2
fi

SERVER_EXE="$INSTALL_PATH/Desynced/Binaries/Win64/DesyncedServer.exe"

if [[ ! -f "$SERVER_EXE" ]]; then
  echo "ERROR: Server executable not found: $SERVER_EXE"
  exit 3
fi

session_settings="{'name': '$SERVER_NAME', 'players':$MAX_PLAYERS, 'visibility': '$VISIBILITY', 'run_without_players': $RUN_WITHOUT_PLAYERS, 'password': '$SERVER_PASSWORD'}"
game_settings="{'resource_amt': $RESOURCE_AMT, 'resource_inf': $RESOURCE_INF, 'blight_threshold': $BLIGHT_THRESHOLD, 'plateau_level': $PLATEAU_LEVEL, 'peaceful': $PEACEFUL_MODE}"

xvfb-run -a \
  wine $INSTALL_PATH/Desynced/Binaries/Win64/DesyncedServer.exe \
  "/saves/$WORLD_NAME.desynced" \
  -SessionSettings="$session_settings" \
  -GameSettings="$game_settings"
