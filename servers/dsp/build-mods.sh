#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$ROOT_DIR/../.." && pwd)

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$REPO_ROOT/.env"
  set +a
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERROR] python3 is required on the host." >&2
  exit 1
fi

DSP_MODS="${DSP_MODS:-nebula-NebulaMultiplayerMod}"
DSP_SERVER_DIR="${DSP_SERVER_DIR:-$ROOT_DIR/data/server}"
DSP_MOD_CACHE_DIR="${DSP_MOD_CACHE_DIR:-$ROOT_DIR/data/mod-cache}"
DSP_MOD_BUNDLE_PATH="${DSP_MOD_BUNDLE_PATH:-$ROOT_DIR/data/mod-cache.tar.gz}"
EXTRA_ZIP_URL="${EXTRA_ZIP_URL:-https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/jobs/4247811310/artifacts/download}"
DSP_MOD_EXTRA_FILE="${DSP_MOD_EXTRA_FILE:-extra.zip}"
DSP_MOD_OFFLINE=0

mkdir -p "$DSP_MOD_CACHE_DIR"

manifest_path="$DSP_MOD_CACHE_DIR/manifest.json"
extra_path="$DSP_MOD_CACHE_DIR/$DSP_MOD_EXTRA_FILE"

echo "[INFO] Building DSP mod cache in $DSP_MOD_CACHE_DIR"
DSP_MODS="$DSP_MODS" \
DSP_SERVER_DIR="$DSP_SERVER_DIR" \
DSP_MOD_CACHE_DIR="$DSP_MOD_CACHE_DIR" \
DSP_MOD_OFFLINE="$DSP_MOD_OFFLINE" \
python3 "$ROOT_DIR/bootstrap.py" build

if [[ -n "$EXTRA_ZIP_URL" ]]; then
  echo "[INFO] Downloading bundled extra artifact to $extra_path"
  EXTRA_ZIP_URL="$EXTRA_ZIP_URL" EXTRA_PATH="$extra_path" python3 - <<'PY'
import os
import shutil
import urllib.request
from pathlib import Path

url = os.environ["EXTRA_ZIP_URL"]
target = Path(os.environ["EXTRA_PATH"])
target.parent.mkdir(parents=True, exist_ok=True)
req = urllib.request.Request(url, headers={"user-agent": "game-server-dsp"})
with urllib.request.urlopen(req, timeout=120) as response, target.open("wb") as output:
    shutil.copyfileobj(response, output)
PY
else
  rm -f "$extra_path"
fi

MANIFEST_PATH="$manifest_path" EXTRA_ZIP_URL="$EXTRA_ZIP_URL" DSP_MOD_EXTRA_FILE="$DSP_MOD_EXTRA_FILE" python3 - <<'PY'
import json
import os
from pathlib import Path

manifest_path = Path(os.environ["MANIFEST_PATH"])
data = json.loads(manifest_path.read_text())
extra_url = os.environ["EXTRA_ZIP_URL"].strip()
if extra_url:
    data["extra"] = {
        "file": os.environ["DSP_MOD_EXTRA_FILE"],
        "source_url": extra_url,
    }
else:
    data["extra"] = None
manifest_path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

rm -f "$DSP_MOD_BUNDLE_PATH"
tar -czf "$DSP_MOD_BUNDLE_PATH" -C "$DSP_MOD_CACHE_DIR" .
echo "[INFO] Packed mod bundle at $DSP_MOD_BUNDLE_PATH"
