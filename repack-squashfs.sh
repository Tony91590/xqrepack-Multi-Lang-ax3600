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


# stop phone-home in web UI
cat <<JS >> "/www/js/miwifi-monitor.js"
(function(){ if (typeof window.MIWIFI_MONITOR !== "undefined") window.MIWIFI_MONITOR.log = function(a,b) {}; })();
JS



# dont start crap services
for SVC in stat_points statisticsservice \
		datacenter \
		smartcontroller \
		plugincenter plugin_start_script.sh cp_preinstall_plugins.sh; do
	rm -f /etc/rc.d/[SK]*$SVC
done

# prevent stats phone home & auto-update
for f in StatPoints mtd_crash_log logupload.lua otapredownload wanip_check.sh; do > /usr/sbin/$f; done

rm -f /etc/hotplug.d/iface/*wanip_check

for f in wan_check messagingagent.sh; do
	sed -i '/start_service(/a return 0' /etc/init.d/$f
done

# cron jobs are mostly non-OpenWRT stuff
for f in /etc/crontabs/*; do
	sed -i 's/^/#/' $f
done

# as a last-ditch effort, change the *.miwifi.com hostnames to localhost
sed -i 's@\w\+.miwifi.com@localhost@g' /etc/config/miwifi


>&2 echo "repacking squashfs..."
rm -f "$IMG.new"
mksquashfs "$FSDIR" "$IMG.new" -comp xz -b 256K -no-xattrs
