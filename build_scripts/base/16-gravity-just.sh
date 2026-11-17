#!/usr/bin/bash
# Adapt ujust recipes and helpers from get-aurora-dev/common to the aurora-gravity
# images (ghcr.io/nihaiden/aurora-gravity{,-dx}, streams latest and stable).
# Each patch replaces exactly one known line and fails the build if upstream
# changed it, so a patch can't silently stop applying.

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

replace_line() {
    python3 - "$@" <<'EOF'
import sys
path, old, new = sys.argv[1:]
lines = open(path).read().split("\n")
if lines.count(old) != 1:
    sys.exit(f"{path}: expected exactly one line {old!r}, found {lines.count(old)}; "
             "it changed upstream, re-check 16-gravity-just.sh")
lines[lines.index(old)] = new
open(path, "w").write("\n".join(lines))
EOF
}

# `ujust toggle-devmode` derives the image to switch to from the part of the image
# name before the first "-" (upstream: aurora-nvidia-open -> aurora-dx-nvidia-open).
# For aurora-gravity that yields ghcr.io/nihaiden/aurora-dx-gravity, which doesn't
# exist. Our DX image is <image-name>-dx (aurora-gravity -> aurora-gravity-dx), and
# there are no nvidia images, so use the full image name as the base.
replace_line /usr/share/ublue-os/just/system.just \
    '    IMAGE_BASE_NAME="$(cut -f1 -d\- <<< "${IMAGE_NAME}")"' \
    '    IMAGE_BASE_NAME="${IMAGE_NAME}" # aurora-gravity: <image>-dx, see 16-gravity-just.sh'

# `ujust rebase-helper` / `ujust switch-stream` offer upstream's image names and the
# testing stream, none of which exist under ghcr.io/nihaiden.
ROLLBACK_HELPER=/usr/bin/ublue-rollback-helper
replace_line "${ROLLBACK_HELPER}" \
    'IMAGES=(aurora aurora-dx aurora-nvidia-open aurora-dx-nvidia-open)' \
    'IMAGES=(aurora-gravity aurora-gravity-dx) # aurora-gravity: see 16-gravity-just.sh'
replace_line "${ROLLBACK_HELPER}" \
    'CHANNELS=(stable latest testing)' \
    'CHANNELS=(stable latest)'
replace_line "${ROLLBACK_HELPER}" \
    '  echo -e "\nstable: The default selection (weekly builds) with gated CoreOS kernel\nlatest: For enthusiast, stock Fedora kernel and latest updates\ntesting: Get a sneak peak into future Aurora builds and Fedora versions\n\nSee our docs: https://docs.getaurora.dev/guides/release-streams\n"' \
    '  echo -e "\nstable: Weekly builds\nlatest: Daily builds with the newest Gravity kernel, Mesa and Fedora updates\n\nSee: https://github.com/NiHaiden/aurora-gravity/blob/gravity/README-GRAVITY.md\n"'
bash -n "${ROLLBACK_HELPER}"

echo "::endgroup::"
