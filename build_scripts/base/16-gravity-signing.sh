#!/usr/bin/bash
# Trust ghcr.io/nihaiden/aurora-gravity{,-dx} images signed with the aurora-gravity
# cosign key, so `bootc upgrade` / uupd can verify them (image-ref uses
# ostree-image-signed:, see 18-image-info.sh). Both repositories are trusted in
# every image so `ujust toggle-devmode` can switch between them with
# --enforce-container-sigpolicy.

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Since Fedora 45, containers-common (and get-aurora-dev/common) ship the policy as
# /usr/share/containers/policy.json only. An /etc copy, if present, takes precedence.
POLICY=/etc/containers/policy.json
[[ -f "${POLICY}" ]] || POLICY=/usr/share/containers/policy.json
test -f "${POLICY}"
KEY=/etc/pki/containers/aurora-gravity.pub
test -f "${KEY}"

GRAVITY_REPOS=(
    ghcr.io/nihaiden/aurora-gravity
    ghcr.io/nihaiden/aurora-gravity-dx
)

for repo in "${GRAVITY_REPOS[@]}"; do
    jq --arg key "${KEY}" --arg repo "${repo}" '.transports.docker[$repo] = [
      {
        "type": "sigstoreSigned",
        "keyPath": $key,
        "signedIdentity": { "type": "matchRepository" }
      }
    ]' "${POLICY}" > "${POLICY}.new"
    mv "${POLICY}.new" "${POLICY}"
done
chmod 0644 "${POLICY}"

for repo in "${GRAVITY_REPOS[@]}"; do
    jq -e --arg repo "${repo}" '.transports.docker[$repo][0].keyPath' "${POLICY}"
done

echo "::endgroup::"
