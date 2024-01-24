#!/usr/bin/env bash

yum install -y libstdc++.so.6
curl -s https://install.zerotier.com | sudo bash
sudo yum install https://download.key-networks.com/el7/ztncui/1/ztncui-release-1-1.noarch.rpm -y
sudo yum install ztncui -y
sudo sh -c "echo ZT_TOKEN=`sudo cat /var/lib/zerotier-one/authtoken.secret` > /opt/key-networks/ztncui/.env"
sudo sh -c "echo HTTPS_PORT=3443 >> /opt/key-networks/ztncui/.env"
sudo sh -c "echo NODE_ENV=production >> /opt/key-networks/ztncui/.env"
sudo chmod 400 /opt/key-networks/ztncui/.env
sudo chown ztncui.ztncui /opt/key-networks/ztncui/.env
sudo systemctl restart ztncui