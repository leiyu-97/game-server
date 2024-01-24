#!/bin/bash

(crontab -l ; echo "${SCHEDULE} /backup.sh") | crontab

touch /var/log/cron.log
service crond start
tail -f /var/log/cron.log