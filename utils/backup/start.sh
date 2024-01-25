#!/bin/bash

sed -i "s/\$MAX_BACKUPS/$MAX_BACKUPS/g" /backup.sh
(crontab -l ; echo "${SCHEDULE} /backup.sh") | crontab

touch /var/log/cron.log
service cron start
tail -f /var/log/cron.log