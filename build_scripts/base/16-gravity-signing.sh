#!/usr/bin/bash
# Trust ghcr.io/nihaiden/aurora-gravity images signed with the aurora-gravity
# cosign key, so `bootc upgrade` / uupd can verify them (image-ref uses
# ostree-image-signed:, see 18-image-info.sh).

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Since Fedora 45, containers-common (and get-aurora-dev/common) ship the policy as
# /usr/share/containers/policy.json only. An /etc copy, if present, takes precedence.
POLICY=/etc/containers/policy.json
[[ -f "${POLICY}" ]] || POLICY=/usr/share/containers/policy.json
test -f "${POLICY}"
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
