#!/usr/bin/env bash

./password.sh || exit
export DOCKER_BUILDKIT=1 

usage(){
cat <<'EOF'
Usage: ./game-server.sh [option] <command>
  -n, --name                  服务名（palworld, teamspeak）
  -h, --help                  帮助

./game-server.sh start             启动
./game-server.sh stop              停止
./game-server.sh restart           重启
./game-server.sh logs              日志
./game-server.sh shell             进入容器
./game-server.sh remove            清除镜像
EOF
}

DIR="$(dirname "$0")"
# 默认值
NAME=docker-example

while [ $1 ]; do
    case "$1" in
        -n|--name)
          NAME=$2
          shift 2
          ;;
        -h|--help)
          usage
          exit
          ;;
        *)
          break
          ;;
    esac
done

if [ ! $1 ];
then
  usage
  exit 1
fi
CMD=$1
shift

export NAME=$NAME
echo NAME: $NAME

case "$CMD" in
    start)
        docker compose -p $NAME -f "${DIR}/servers/${NAME}/docker-compose.yml" up -d --build
        docker compose -f "${DIR}/servers/${NAME}/docker-compose.yml" logs -t -f
        ;;
    stop)
        docker compose  -p $NAME -f "${DIR}/servers/${NAME}/docker-compose.yml" down
        ;;
    restart)
        docker compose  -p $NAME -f "${DIR}/servers/${NAME}/docker-compose.yml" down
        docker compose  -p $NAME -f "${DIR}/servers/${NAME}/docker-compose.yml" up -d --build
        docker compose -f "${DIR}/servers/${NAME}/docker-compose.yml" logs -t -f
        ;;
    remove)
        docker compose  -p $NAME -f "${DIR}/servers/${NAME}/docker-compose.yml" down
        docker image rm $(docker images --format "{{.Repository}}" | grep $NAME)
        ;;
    shell)
        docker exec -ti $NAME /bin/bash
        ;;
    logs)
        docker compose -f "${DIR}/servers/${NAME}/docker-compose.yml" logs -t -f
        ;;
    *)
      usage
      ;;
esac
