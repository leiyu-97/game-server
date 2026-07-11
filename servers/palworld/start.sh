#!/bin/bash
GAME_PATH=/palworld
STEAM_PROXY_URL=http://xray:10809
# Steam content downloads bypass both the process proxy and Mihomo's proxy rule.
STEAM_CONTENT_NO_PROXY=localhost,127.0.0.1,::1,steamcontent.com,.steamcontent.com,steamcdn-a.akamaihd.net,.steamcdn-a.akamaihd.net,steamcdn.com,.steamcdn.com,steamstatic.com,.steamstatic.com

steamcmd_with_proxy() {
  HTTP_PROXY="$STEAM_PROXY_URL" \
  HTTPS_PROXY="$STEAM_PROXY_URL" \
  http_proxy="$STEAM_PROXY_URL" \
  https_proxy="$STEAM_PROXY_URL" \
  NO_PROXY="$STEAM_CONTENT_NO_PROXY" \
  no_proxy="$STEAM_CONTENT_NO_PROXY" \
  steamcmd "$@"
}

chown -R steam:root /PalWorldSettings.ini
steamcmd_with_proxy +force_install_dir "$GAME_PATH" +login anonymous +app_update 2394010 validate +quit
chown -R steam:root $GAME_PATH
cp /PalWorldSettings.ini $GAME_PATH/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
sed -i "s/ServerPassword=\"[^\"]*\"/ServerPassword=\"$SERVER_PASSWORD\"/" ${GAME_PATH}/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
sed -i "s/AdminPassword=\"[^\"]*\"/AdminPassword=\"$ADMIN_PASSWORD\"/" ${GAME_PATH}/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
su steam -c "HTTP_PROXY=$STEAM_PROXY_URL HTTPS_PROXY=$STEAM_PROXY_URL http_proxy=$STEAM_PROXY_URL https_proxy=$STEAM_PROXY_URL NO_PROXY=$STEAM_CONTENT_NO_PROXY no_proxy=$STEAM_CONTENT_NO_PROXY /home/steam/.steam/steamcmd.sh +login anonymous +quit"
su steam -c "$GAME_PATH/PalServer.sh -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS"
