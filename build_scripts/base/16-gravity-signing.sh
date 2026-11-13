#!/usr/bin/bash
# Trust ghcr.io/nihaiden/aurora-gravity images signed with the aurora-gravity
# cosign key, so `bootc upgrade` / uupd can verify them (image-ref uses
# ostree-image-signed:, see 18-image-info.sh).

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

POLICY=/etc/containers/policy.json
KEY=/etc/pki/containers/aurora-gravity.pub
test -f "${KEY}"

jq --arg key "${KEY}" '.transports.docker["ghcr.io/nihaiden/aurora-gravity"] = [
  {
    "type": "sigstoreSigned",
    "keyPath": $key,
    "signedIdentity": { "type": "matchRepository" }
  }
]' "${POLICY}" > "${POLICY}.new"
mv "${POLICY}.new" "${POLICY}"
chmod 0644 "${POLICY}"

jq -e '.transports.docker["ghcr.io/nihaiden/aurora-gravity"][0].keyPath' "${POLICY}"

echo "::endgroup::"
