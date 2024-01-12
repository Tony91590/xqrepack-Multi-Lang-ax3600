#!/bin/sh
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
sed -i 's/channel=.*/channel=release2/' "/etc/init.d/dropbear"
sed -i 's/flg_ssh=.*/flg_ssh=1/' "/etc/init.d/dropbear"

# stop resetting root password
sed -i '/set_user(/a return 0' "/etc/init.d/system"
sed -i 's/flg_init_pwd=.*/flg_init_pwd=0/' "/etc/init.d/boot_check"

cp -R lib/* "$FSDIR/lib/"

sed -i 's/149/132/' "$FSDIR/usr/lib/lua/luci/view/web/setting/wifi.htm"
sed -i 's/149/132/' "$FSDIR/usr/lib/lua/luci/view/web/apsetting/wifi.htm"
sed -i 's/149/132/' "$FSDIR/usr/lib/lua/luci/view/web/inc/wifi.html"

# apply patch from xqrepack repository
find patches -type f -exec bash -c "(cd "$FSDIR" && patch -p1) < {}" \;
find patches -type f -name \*.orig -delete

rm -f $FSDIR/etc/config/xqled.orig
rm -f $FSDIR/lib/wifi/qcawificfg80211.sh.orig
rm -f $FSDIR/usr/lib/lua/luci/view/web/apsetting/wifi.htm.orig
rm -f $FSDIR/usr/lib/lua/luci/view/web/inc/wifi.html.orig
rm -f $FSDIR/usr/lib/lua/luci/view/web/setting/wifi.htm.orig

>&2 echo "repacking squashfs..."
rm -f "$IMG.new"
mksquashfs "$FSDIR" "$IMG.new" -comp xz -b 256K -no-xattrs
