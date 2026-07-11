# Clash-compatible selective proxy

The `xray` service runs [Mihomo](https://github.com/MetaCubeX/mihomo), the
actively maintained Clash Meta runtime. It directly loads the top-level
`proxies` list in `clash.yaml`; nodes are not converted to Xray JSON. The service
exposes a SOCKS5 proxy on port `10808` and an HTTP proxy on port `10809`.

Requests matching the project-owned `proxy-whitelist.yaml` use one selected
Clash node; every other request uses the local `DIRECT` connection.

SteamCMD login and update commands in Palworld, Desynced, and the DSP installer
use `http://xray:10809` through the shared `game-server-proxy` Docker network.
Steam content CDNs are bypassed twice: each SteamCMD process has matching
`NO_PROXY` entries, and [`steam-download-direct.yaml`](steam-download-direct.yaml)
is evaluated before the proxy whitelist. Game payload downloads therefore use
the direct connection.

## Configure and start

1. Copy the template and fill in real Clash nodes:

   ```sh
   cd servers/xray
   cp clash.example.yaml clash.yaml
   ```

   Any node type supported by the installed Mihomo release is accepted, including
   VLESS/REALITY, VMess, Trojan, Shadowsocks and Hysteria. `PROJECT_PROXY`
   contains the nodes from this file and uses the first entry by default. Move
   the preferred node to the top and restart the service to change that default.

2. Maintain `proxy-whitelist.yaml`, a native Clash/Mihomo `classical` rule
   provider. For example, `DOMAIN-SUFFIX,github.com` covers GitHub and all of
   its subdomains; it also accepts `DOMAIN`, `DOMAIN-KEYWORD`, `IP-CIDR`,
   `GEOIP`, and other classical rule types.

3. Start from the repository root:

   ```sh
   ./proxy.sh start
   ```

[`config.yaml`](config.yaml) is the committed static Mihomo configuration.
Restart the service after changing either `clash.yaml` or the whitelist.

### Offline deployment on x86_64 Linux

The repository includes `images/mihomo-v1.19.27-linux-amd64.tar`. Copy the
repository to the server, configure `clash.yaml`, then run:

```sh
chmod +x servers/xray/load-image.sh
./servers/xray/load-image.sh
```

The script verifies an x86_64 host, loads the local image archive, verifies its
architecture, and starts the service. It avoids downloading the Mihomo image
from Docker Hub during deployment.

## Docker image pulls

From the repository root, run:

```sh
./proxy.sh daemon-enable
```

This starts Mihomo and installs a dedicated, reversible Docker systemd drop-in
at `/etc/systemd/system/docker.service.d/game-server-proxy.conf`. Docker image
pulls then use `http://127.0.0.1:10809`; the script restarts Docker so the
setting takes effect. Remove it at any time with:

```sh
./proxy.sh daemon-disable
```

The proxy ports are fixed to `127.0.0.1` because the inbounds have no
authentication. Mihomo permits Docker bridge connections so that Docker daemon
requests can reach the proxy, but the host-side binding still prevents external
network access. Change the host-side bindings in `docker-compose.yml` only if
access is protected by a firewall or trusted private network.

## Use the proxy after startup

For ordinary command-line tools on the same host, use the HTTP proxy:

```sh
export HTTP_PROXY=http://127.0.0.1:10809
export HTTPS_PROXY=http://127.0.0.1:10809
export NO_PROXY=localhost,127.0.0.1,::1
```

Alternatively, clients that support SOCKS5 can use
`socks5h://127.0.0.1:10808`; the `h` makes the client send the original domain
to Mihomo so whitelist domain rules work reliably.

To proxy `docker pull` on a Linux host, configure the Docker daemon with the
same HTTP proxy address, then reload and restart Docker:

```ini
# /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:10809"
Environment="HTTPS_PROXY=http://127.0.0.1:10809"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
```

```sh
sudo systemctl daemon-reload
sudo systemctl restart docker
```

Confirm that the service is reachable with:

```sh
curl -x http://127.0.0.1:10809 https://registry-1.docker.io/v2/
```

An HTTP `401 Unauthorized` response from the registry is expected and confirms
that the request reached Docker Hub.

## Routing order

1. Whitelist rules use the selected `PROJECT_PROXY` node.
2. A final `MATCH,DIRECT` rule sends everything else directly.
