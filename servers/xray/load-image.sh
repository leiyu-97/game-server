#!/usr/bin/env bash

set -euo pipefail

log() { printf '[xray-image] %s\n' "$*"; }
fail() { printf '[xray-image] ERROR: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE="metacubex/mihomo:v1.19.27"
ARCHIVE="$SCRIPT_DIR/images/mihomo-v1.19.27-linux-amd64.tar"

case "$(uname -m)" in
  x86_64 | amd64) ;;
  *) fail "This archive is linux/amd64, but the host architecture is $(uname -m)." ;;
esac

[[ -f "$ARCHIVE" ]] || fail "Image archive not found: $ARCHIVE"
[[ -f "$SCRIPT_DIR/clash.yaml" ]] || fail "Missing $SCRIPT_DIR/clash.yaml; copy and configure clash.example.yaml first."

log "Loading $ARCHIVE"
docker load -i "$ARCHIVE"

loaded_architecture="$(docker image inspect "$IMAGE" --format '{{.Architecture}}')"
[[ "$loaded_architecture" == "amd64" ]] || fail "Loaded image architecture is $loaded_architecture, expected amd64."

log "Starting xray service"
exec "$REPO_ROOT/game-server.sh" -n xray start
