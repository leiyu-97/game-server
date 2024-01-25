#!/bin/bash

# 定义备份目录和文件
BACKUP_DIR="/target"
SOURCE_DIR="/source"

echo "$(date "+%Y-%m-%d %H:%M:%S") INFO: Starting backup process..." > /backup.log

# 创建备份
tar -czf $BACKUP_DIR/$(date +%Y%m%d%H%M%S).tar.gz $SOURCE_DIR
echo "$(date "+%Y-%m-%d %H:%M:%S") INFO: Backup created for $SOURCE_DIR"  > /backup.log

# 删除旧的备份
BACKUPS=$(ls $BACKUP_DIR/*.tar.gz | wc -l)
while [ $BACKUPS -gt $MAX_BACKUPS ]
do
    OLDEST=$(ls $BACKUP_DIR/*.tar.gz | head -1)
    rm $OLDEST
    echo "$(date "+%Y-%m-%d %H:%M:%S") INFO: Deleted oldest backup: $OLDEST" /backup.log
    BACKUPS=$(ls $BACKUP_DIR/*.tar.gz | wc -l)
done

echo "$(date "+%Y-%m-%d %H:%M:%S") INFO: Backup process finished." /backup.log