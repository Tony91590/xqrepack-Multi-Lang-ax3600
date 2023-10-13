#!/usr/bin/env bash
#
# unpack, modify and re-pack the Xiaomi R3600 firmware
# removes checks for release channel before starting dropbear
#
# 2020.07.20  darell tan
# 

set -e

IMG=$1
ROOTPW='$1$qtLLI4cm$c0v3yxzYPI46s28rbAYG//'  # "password"

[ -e "$IMG" ] || { echo "rootfs img not found $IMG"; exit 1; }

# verify programs exist
command -v unsquashfs &>/dev/null || { echo "install unsquashfs"; exit 1; }
mksquashfs -version >/dev/null || { echo "install mksquashfs"; exit 1; }

FSDIR=`mktemp -d /tmp/resquash-rootfs.XXXXX`
trap "rm -rf $FSDIR" EXIT

# test mknod privileges
mknod "$FSDIR/foo" c 0 0 2>/dev/null || { echo "need to be run with fakeroot"; exit 1; }
rm -f "$FSDIR/foo"

>&2 echo "unpacking squashfs..."
unsquashfs -f -d "$FSDIR" "$IMG"

>&2 echo "patching squashfs..."

# modify dropbear init
sed -i 's/channel=.*/channel=release2/' "$FSDIR/etc/init.d/dropbear"
sed -i 's/flg_ssh=.*/flg_ssh=1/' "$FSDIR/etc/init.d/dropbear"

# mark web footer so that users can confirm the right version has been flashed
sed -i 's/romVersion%>/& xqrepack/;' "$FSDIR/usr/lib/lua/luci/view/web/inc/footer.htm"

# stop resetting root password
sed -i '/set_user(/a return 0' "$FSDIR/etc/init.d/system"
sed -i 's/flg_init_pwd=.*/flg_init_pwd=0/' "$FSDIR/etc/init.d/boot_check"

# modify root password
sed -i "s@root:[^:]*@root:${ROOTPW}@" "$FSDIR/etc/shadow"

# wifi TX-power
cp -R lib/* "$FSDIR/lib/"

# add xqflash tool into firmware for easy upgrades
cp xqflash "$FSDIR/sbin"
chmod 0755      "$FSDIR/sbin/xqflash"
chown root:root "$FSDIR/sbin/xqflash"

>&2 echo "repacking squashfs..."
rm -f "$IMG.new"
mksquashfs "$FSDIR" "$IMG.new" -comp xz -b 256K -no-xattrs
