#!/bin/sh
#
# unpack, modify and re-pack the Xiaomi R3600 firmware
# removes checks for release channel before starting dropbear
#
# 2020.07.20  darell tan
# 

set -e

IMG=$1

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

# stop phone-home in web UI
cat <<JS >> "$FSDIR/www/js/miwifi-monitor.js"
(function(){ if (typeof window.MIWIFI_MONITOR !== "undefined") window.MIWIFI_MONITOR.log = function(a,b) {}; })();
JS

# dont start crap services
for SVC in stat_points statisticsservice \
		datacenter \
		smartcontroller \
		wan_check \
		plugincenter plugin_start_script.sh cp_preinstall_plugins.sh; do
	rm -f $FSDIR/etc/rc.d/[SK]*$SVC
done

# prevent stats phone home & auto-update
for f in StatPoints mtd_crash_log logupload.lua otapredownload wanip_check.sh; do > $FSDIR/usr/sbin/$f; done

rm -f $FSDIR/etc/hotplug.d/iface/*wanip_check

sed -i '/start_service(/a return 0' $FSDIR/etc/init.d/messagingagent.sh

# cron jobs are mostly non-OpenWRT stuff
for f in $FSDIR/etc/crontabs/*; do
	sed -i 's/^/#/' $f
done

# as a last-ditch effort, change the *.miwifi.com hostnames to localhost
sed -i 's@\w\+.miwifi.com@localhost@g' $FSDIR/etc/config/miwifi

# wifi TX-power
cp -R lib/* "$FSDIR/lib/"

# led wan check on
cp -R etc/* "$FSDIR/etc/"

>&2 echo "repacking squashfs..."
rm -f "$IMG.new"
mksquashfs "$FSDIR" "$IMG.new" -comp xz -b 256K -no-xattrs
