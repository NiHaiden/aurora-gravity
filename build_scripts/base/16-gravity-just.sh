#!/usr/bin/bash
# Adapt ujust recipes from get-aurora-dev/common to the aurora-gravity image names.

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

SYSTEM_JUST=/usr/share/ublue-os/just/system.just

# `ujust toggle-devmode` derives the image to switch to from the part of the image
# name before the first "-" (upstream: aurora-nvidia-open -> aurora-dx-nvidia-open).
# For aurora-gravity that yields ghcr.io/nihaiden/aurora-dx-gravity, which doesn't
# exist. Our DX image is <image-name>-dx (aurora-gravity -> aurora-gravity-dx), and
# there are no nvidia images, so use the full image name as the base.
UPSTREAM_LINE='    IMAGE_BASE_NAME="$(cut -f1 -d\- <<< "${IMAGE_NAME}")"'
GRAVITY_LINE='    IMAGE_BASE_NAME="${IMAGE_NAME}" # aurora-gravity: <image>-dx, see 16-gravity-just.sh'

if ! grep -qxF -- "${UPSTREAM_LINE}" "${SYSTEM_JUST}"; then
    echo "toggle-devmode in ${SYSTEM_JUST} changed upstream; re-check 16-gravity-just.sh"
    exit 1
fi

python3 - "${SYSTEM_JUST}" "${UPSTREAM_LINE}" "${GRAVITY_LINE}" <<'EOF'
import sys
path, old, new = sys.argv[1:]
lines = open(path).read().split("\n")
assert lines.count(old) == 1, f"expected exactly one {old!r}"
lines[lines.index(old)] = new
open(path, "w").write("\n".join(lines))
EOF

grep -qxF -- "${GRAVITY_LINE}" "${SYSTEM_JUST}"

echo "::endgroup::"
