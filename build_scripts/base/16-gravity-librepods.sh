#!/usr/bin/bash
# LibrePods: the binary is built in the librepods stage of Containerfile.in
# (build_scripts/librepods/build.sh). Here we only enable VendorID spoofing.
#
# Advertise Apple's Bluetooth vendor ID (0x004C) in the DID profile so AirPods
# unlock extra features (e.g. Loud Sound Reduction, hearing aid/accessibility
# settings). See https://github.com/librepods-org/librepods#vendorid-spoofing
# Note: this makes the machine identify as an Apple device to *every* Bluetooth
# peer, and AirPods may need to be re-paired because they cache the DeviceID.

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

BT_MAIN_CONF=/etc/bluetooth/main.conf
DEVICE_ID_LINE='DeviceID = bluetooth:004C:0000:0000'

if grep -qE '^[#[:space:]]*DeviceID[[:space:]]*=' "${BT_MAIN_CONF}"; then
    sed -i -E "0,/^[#[:space:]]*DeviceID[[:space:]]*=.*/s//${DEVICE_ID_LINE}/" "${BT_MAIN_CONF}"
else
    sed -i "/^\[General\]/a ${DEVICE_ID_LINE}" "${BT_MAIN_CONF}"
fi
grep -qx "${DEVICE_ID_LINE}" "${BT_MAIN_CONF}"

echo "::endgroup::"
