#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XRAY_DIR="$ROOT_DIR/servers/xray"
IMAGE="metacubex/mihomo:v1.19.27"
IMAGE_ARCHIVE="$XRAY_DIR/images/mihomo-v1.19.27-linux-amd64.tar"
DOCKER_DROPIN="/etc/systemd/system/docker.service.d/game-server-proxy.conf"
PROXY_NETWORK="game-server-proxy"
COMPOSE=(docker compose -p xray -f "$XRAY_DIR/docker-compose.yml")

log() { printf '[proxy] %s\n' "$*"; }
fail() { printf '[proxy] ERROR: %s\n' "$*" >&2; exit 1; }

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

require_x86_64() {
  case "$(uname -m)" in
    x86_64 | amd64) ;;
    *) fail "The bundled Mihomo image requires x86_64/amd64, got $(uname -m)." ;;
  esac
}

load_image() {
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    return
  fi

  [[ -f "$IMAGE_ARCHIVE" ]] || fail "Image archive not found: $IMAGE_ARCHIVE"
  log "Loading offline Mihomo image"
  docker load -i "$IMAGE_ARCHIVE"
}

start_proxy() {
  require_x86_64
  [[ -f "$XRAY_DIR/clash.yaml" ]] || fail "Missing $XRAY_DIR/clash.yaml; copy and configure clash.example.yaml first."
  load_image

  if ! docker network inspect "$PROXY_NETWORK" >/dev/null 2>&1; then
    log "Creating shared Docker network $PROXY_NETWORK"
    docker network create "$PROXY_NETWORK" >/dev/null
  fi

  local image_architecture
  image_architecture="$(docker image inspect "$IMAGE" --format '{{.Architecture}}')"
  [[ "$image_architecture" == "amd64" ]] || fail "Loaded image architecture is $image_architecture, expected amd64."

  log "Starting Mihomo proxy"
  "${COMPOSE[@]}" up -d
  "${COMPOSE[@]}" ps
}

restart_docker() {
  as_root systemctl daemon-reload
  as_root systemctl restart docker
  as_root systemctl is-active --quiet docker || fail "Docker did not become active after restart."
}

enable_daemon_proxy() {
  start_proxy
  log "Configuring Docker daemon to use http://127.0.0.1:10809"
  as_root install -d -m 0755 "$(dirname "$DOCKER_DROPIN")"
  as_root tee "$DOCKER_DROPIN" >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:10809"
Environment="HTTPS_PROXY=http://127.0.0.1:10809"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
  restart_docker
  log "Docker daemon proxy enabled."
}

disable_daemon_proxy() {
  if [[ ! -e "$DOCKER_DROPIN" ]]; then
    log "Docker daemon proxy drop-in is already absent."
    return
  fi

  log "Removing project Docker daemon proxy configuration"
  as_root rm -f "$DOCKER_DROPIN"
  restart_docker
  log "Docker daemon proxy disabled."
}

usage() {
  cat <<'EOF'
Usage: ./proxy.sh <command>

Commands:
  start          Load the bundled amd64 Mihomo image if needed and start the proxy.
  restart        Recreate the proxy container and apply its latest Compose/config files.
  daemon-enable  Start the proxy, then make Docker image pulls use it.
  daemon-disable Remove only this project's Docker systemd proxy drop-in.
  stop           Stop the proxy container.
  status         Show proxy container status and daemon proxy drop-in status.
EOF
}

case "${1:-}" in
  start)
    start_proxy
    ;;
  restart)
    log "Recreating Mihomo proxy"
    "${COMPOSE[@]}" down
    start_proxy
    ;;
  daemon-enable)
    enable_daemon_proxy
    ;;
  daemon-disable)
    disable_daemon_proxy
    ;;
  stop)
    "${COMPOSE[@]}" down
    ;;
  status)
    "${COMPOSE[@]}" ps
    if [[ -f "$DOCKER_DROPIN" ]]; then
      log "Docker daemon proxy: enabled ($DOCKER_DROPIN)"
    else
      log "Docker daemon proxy: disabled"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
