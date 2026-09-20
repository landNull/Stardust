#!/bin/sh
# Compatibility wrapper. The host bootstrap is install-stardust.sh.
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$HERE/install-stardust.sh" "$@"
