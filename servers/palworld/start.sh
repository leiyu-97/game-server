#!/bin/bash
GAME_PATH=/palworld

chown -R steam:root /PalWorldSettings.ini
steamcmd +force_install_dir $GAME_PATH +login anonymous +app_update 2394010 validate +quit
chown -R steam:root $GAME_PATH
cp /PalWorldSettings.ini $GAME_PATH/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
sed -i "s/ServerPassword=\"[^\"]*\"/ServerPassword=\"$SERVER_PASSWORD\"/" ${GAME_PATH}/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
sed -i "s/AdminPassword=\"[^\"]*\"/AdminPassword=\"$ADMIN_PASSWORD\"/" ${GAME_PATH}/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
su steam -c "/home/steam/.steam/steamcmd.sh +login anonymous +quit"
su steam -c "$GAME_PATH/PalServer.sh -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS"