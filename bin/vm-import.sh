#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
exec "$BASE_DIR/bin/vmctl.sh" import "$@"
