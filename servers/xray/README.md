# Clash-compatible selective proxy

The `xray` service now runs [Mihomo](https://github.com/MetaCubeX/mihomo), the
actively maintained Clash Meta runtime. It reads a standard Clash YAML directly,
so nodes are not converted to Xray JSON. The service exposes a SOCKS5 proxy on
port `10808` and an HTTP proxy on port `10809`.

Requests matching the project-owned `proxy-whitelist.yaml` use one selected
Clash node; every other request uses the local `DIRECT` connection.

## Configure and start

1. Copy the template and fill in real Clash nodes:

   ```sh
   cd servers/xray
   cp clash.example.yaml clash.yaml
   ```

   Any node type supported by the installed Mihomo release is accepted, including
   VLESS/REALITY, VMess, Trojan, Shadowsocks and Hysteria. `PROJECT_PROXY`
   contains every entry in the top-level `proxies` list and uses the first entry
   by default. Move the preferred node to the top and restart the service to
   change that default.

2. Maintain `proxy-whitelist.yaml`, a native Clash/Mihomo `classical` rule
   provider. For example, `DOMAIN-SUFFIX,github.com` covers GitHub and all of
   its subdomains; it also accepts `DOMAIN`, `DOMAIN-KEYWORD`, `IP-CIDR`,
   `GEOIP`, and other classical rule types.

3. Start from the repository root:

   ```sh
   ./game-server.sh -n xray start
   ```

The generated Mihomo configuration is written to `runtime/config.yaml`; do not
edit it directly. Restart the service after changing either `clash.yaml` or the
whitelist.

The proxy ports are fixed to `127.0.0.1` because the inbounds have no
authentication. Change the host-side bindings in `docker-compose.yml` only if
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
