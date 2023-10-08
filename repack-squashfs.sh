#!/bin/sh
#
# unpack, modify and re-pack the Xiaomi R6000 firmware
# removes checks for release channel before starting dropbear
#
# 2020.07.20  darell tan
# 

set -e

IMG=$1
ROOTPW="$PASSWORD"  # "password"
SCRIPT_ROOT_DIR="$PWD"

[ -e "$IMG" ] || { echo "rootfs img not found $IMG"; exit 1; }

# verify programs exist
command -v unsquashfs &>/dev/null || { echo "install unsquashfs"; exit 1; }
mksquashfs -version >/dev/null || { echo "install mksquashfs"; exit 1; }

FSDIR=`mktemp -d /tmp/resquash-rootfs.XXXXX`
echo "FSDIR: $FSDIR"
trap "rm -rf $FSDIR" EXIT

# test mknod privileges
mknod "$FSDIR/foo" c 0 0 2>/dev/null || { echo "need to be run with fakeroot"; exit 1; }
rm -f "$FSDIR/foo"

>&2 echo "unpacking squashfs..."
unsquashfs -f -d "$FSDIR" "$IMG"
###############################################################################

>&2 echo "patching squashfs..."

# add global firmware language packages
cp -R ./uci-defaults/. $FSDIR/etc/uci-defaults
chmod 755 $FSDIR/etc/uci-defaults/luci-i18n-*

>&2 echo "repacking squashfs..."
rm -f "$IMG.new"
mksquashfs "$FSDIR" "$IMG.new" -comp xz -b 256K -no-xattrs
