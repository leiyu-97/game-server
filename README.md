# game-server

```shell
# 启动服务
./game-server.sh -n palworld start
```

```shell
Usage: ./game-server.sh [option] <command>
  -n, --name                  服务名（palworld, teamspeak）
  -h, --help                  帮助

./game-server.sh start             启动
./game-server.sh stop              停止
./game-server.sh restart           重启
./game-server.sh logs              日志
./game-server.sh shell             进入容器
./game-server.sh remove            清除镜像
```