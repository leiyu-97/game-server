#!/usr/bin/env bash

export DOCKER_BUILDKIT=1

usage() {
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

ROOT_DIR=$(readlink -f "$(dirname "$0")")
# 默认值
NAME=docker-example

while [ $1 ]; do
  case "$1" in
  -n | --name)
    NAME=$2
    shift 2
    ;;
  -h | --help)
    usage
    exit
    ;;
  *)
    break
    ;;
  esac
done

if [ ! $1 ]; then
  usage
  exit 1
fi
CMD=$1
shift

echo NAME: $NAME
if [ "$CMD" = "status" ]; then
  CMD="logs"
fi

DIR="${ROOT_DIR}/servers/${NAME}/"

cat <<EOF >.temp_env
DIR=${DIR}
ROOT_DIR=${ROOT_DIR}
EOF

COMMON_PARAMS="--env-file ./.env --env-file ./.temp_env -p $NAME -f $DIR/docker-compose.yml"

case "$CMD" in
start)
  docker compose $COMMON_PARAMS up -d --build
  docker compose $COMMON_PARAMS logs -t -f
  ;;
stop)
  docker compose $COMMON_PARAMS down
  ;;
restart)
  docker compose $COMMON_PARAMS down
  docker compose $COMMON_PARAMS up -d --build
  docker compose $COMMON_PARAMS logs -t -f
  ;;
remove)
  docker compose $COMMON_PARAMS down
  docker image rm $(docker compose $COMMON_PARAMS images --quiet)
  ;;
shell)
  docker exec -ti $NAME /bin/bash
  ;;
logs)
  docker compose $COMMON_PARAMS logs -t -f
  ;;
*)
  usage
  ;;
esac
