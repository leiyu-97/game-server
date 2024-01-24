FROM ubuntu:18.04

# 安装cron
RUN apt-get update && apt-get -y install cron

ADD start.sh /start.sh
ADD backup.sh /backup.sh
RUN chmod +x /start.sh /backup.sh

# 运行cron
CMD ["/start.sh"]