#!/bin/bash
set -e

mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200
chmod 600 /dev/net/tun

export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1
wg-quick down wg0 || true
wg-quick up wg0 || { echo "!!! Failed to bring up tunnel"; exit 1; }

tail -f /dev/null
