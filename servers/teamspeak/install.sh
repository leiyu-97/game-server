#!/usr/bin/env bash

DOWNLOAD_LINK=https://files.teamspeak-services.com/releases/server/3.13.7/teamspeak3-server_linux_amd64-3.13.7.tar.bz2

useradd teamspeak
if [ ! -f "/home/teamspeak/teamspeak/ts3server_startscript.sh" ]; then
	wget -O teamspeak3.tar.bz2 $DOWNLOAD_LINK --no-check-certificate
	tar -xjvf teamspeak3.tar.bz2
	mv teamspeak3-server_linux_amd64/* /home/teamspeak/teamspeak/
	echo 'license_accepted=1' > /home/teamspeak/teamspeak/.ts3server_license_accepted
else
  rm /home/teamspeak/teamspeak/ts3server.pid
fi

chown -R teamspeak:teamspeak /home/teamspeak/teamspeak
cd /home/teamspeak/teamspeak
su teamspeak -c "./ts3server daemon=0 pid_file=./ts3server.pid"
