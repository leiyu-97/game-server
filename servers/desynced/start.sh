#! /bin/bash

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

session_settings="{'name': '$SERVER_NAME', 'players':$MAX_PLAYERS, 'visibility': '$VISIBILITY', 'run_without_players': $RUN_WITHOUT_PLAYERS}"
game_settings="{'resource_richness': $RESOURCE_RICHNESS, 'blight_threshold': $BLIGHT_THRESHOLD, 'plateau_level': $PLATEAU_LEVEL, 'peaceful': $PEACEFUL_MODE}"

xvfb-run -a \
  wine $INSTALL_PATH/Desynced/Binaries/Win64/DesyncedServer.exe \
  "$WORLD_NAME.desynced" \
  -SessionSettings="$session_settings" \
  -GameSettings="$game_settings"