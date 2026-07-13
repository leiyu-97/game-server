# game-server

```shell
# 启动服务
./game-server.sh -n palworld start
```

```shell
Usage: ./game-server.sh [option] <command>
  -n, --name                  服务名（palworld, teamspeak, xray）
  -h, --help                  帮助

./game-server.sh start             启动
./game-server.sh stop              停止
./game-server.sh restart           重启
./game-server.sh logs              日志
./game-server.sh shell             进入容器
./game-server.sh remove            清除镜像
```

## Proxy

Run `./proxy.sh start` to load and start the project-local Mihomo proxy; use
`./proxy.sh restart` to recreate it after changing its configuration. Run
`./proxy.sh daemon-enable` to additionally configure Docker's daemon, through a
reversible project-named systemd drop-in, so image pulls use that proxy. Remove
the setting with `./proxy.sh daemon-disable`.

## DSP

Set `STEAM_USER` and `STEAM_PASS` in `.env`, then run:

```shell
./game-server.sh -n dsp start
```

The DSP container downloads the game and Nebula dependency chain directly into
`servers/dsp/data` on its first start. Later starts reuse those files and only
download a newly released Nebula package when Thunderstore reports one.
