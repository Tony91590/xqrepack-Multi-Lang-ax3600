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

# create /opt dir
mkdir "$FSDIR/opt"
chmod 755 "$FSDIR/opt"

# create /layout dir
mkdir "$FSDIR/layout"

# modify dropbear init
sed -i 's/channel=.*/channel=release2/' "$FSDIR/etc/init.d/dropbear"
sed -i 's/flg_ssh=.*/flg_ssh=1/' "$FSDIR/etc/init.d/dropbear"

# mark web footer so that users can confirm the right version has been flashed
sed -i 's/romVersion%>/& evgenkitz/;' "$FSDIR/usr/lib/lua/luci/view/web/inc/footer.htm"

# stop resetting root password
sed -i '/set_user(/a return 0' "$FSDIR/etc/init.d/system"

# make sure our backdoors are always enabled by default
sed -i '/ssh_en/d;' "$FSDIR/usr/share/xiaoqiang/xiaoqiang-reserved.txt"
sed -i '/ssh_en=/d; /uart_en=/d; /boot_wait=/d;' "$FSDIR/usr/share/xiaoqiang/xiaoqiang-defaults.txt"
cat <<XQDEF >> "$FSDIR/usr/share/xiaoqiang/xiaoqiang-defaults.txt"
uart_en=1
ssh_en=1
boot_wait=on
XQDEF

# always reset our access nvram variables
grep -q -w enable_dev_access "$FSDIR/lib/preinit/31_restore_nvram" || \
 cat <<NVRAM >> "$FSDIR/lib/preinit/31_restore_nvram"
enable_dev_access() {
	nvram set uart_en=1
	nvram set ssh_en=1
	nvram set boot_wait=on
	nvram commit
}

boot_hook_add preinit_main enable_dev_access
NVRAM

# modify root password
if [ -n "ROOTPW" ]
then
	sed -i "s@root:[^:]*@root:${ROOTPW}@" "$FSDIR/etc/shadow"
else
	echo -e "\033[0;31mROOT Password hasn't been changed!!!\033[0m\nTo modify this password please define it in ROOTPW env variable"
fi

# stop phone-home in web UI
#cat <<JS >> "$FSDIR/www/js/miwifi-monitor.js"
#(function(){ if (typeof window.MIWIFI_MONITOR !== "undefined") window.MIWIFI_MONITOR.log = function(a,b) {}; })();
#JS

# add xqflash tool into firmware for easy upgrades
cp xqflash "$FSDIR/sbin"
chmod 0755      "$FSDIR/sbin/xqflash"
chown root:root "$FSDIR/sbin/xqflash"

# dont start crap services
#for SVC in stat_points statisticsservice \
#		datacenter \
#		smartcontroller \
#		wan_check \
#		plugincenter plugin_start_script.sh cp_preinstall_plugins.sh; do
#	rm -f $FSDIR/etc/rc.d/[SK]*$SVC
#done

# prevent stats phone home & auto-update
#for f in StatPoints mtd_crash_log logupload.lua otapredownload wanip_check.sh; do > $FSDIR/usr/sbin/$f; done

# prevent auto-update
> $FSDIR/usr/sbin/otapredownload

#rm -f $FSDIR/etc/hotplug.d/iface/*wanip_check

#sed -i '/start_service(/a return 0' $FSDIR/etc/init.d/messagingagent.sh

# cron jobs are mostly non-OpenWRT stuff
#for f in $FSDIR/etc/crontabs/*; do
#	sed -i 's/^/#/' $f
#done

# as a last-ditch effort, change the *.miwifi.com hostnames to localhost
#sed -i 's@\w\+.miwifi.com@localhost@g' $FSDIR/etc/config/miwifi

if grep -q model=RA72 $FSDIR/usr/share/xiaoqiang/xiaoqiang-defaults.txt; then
	echo "patch: $FSDIR/lib/preinit/90_mount_bind_etc"
	patch $FSDIR/lib/preinit/90_mount_bind_etc "$SCRIPT_ROOT_DIR/patches/90_mount_bind_etc.patch"
fi

python translate/translate.py $FSDIR

die()
{
	echo "$1"
	exit 1
}

#install packages
PACKAGES_TO_INSTALL=$(find packages -name '*.ipk' 2>-)
if [ -n "$PACKAGES_TO_INSTALL" ]; then
	TMP_DIR=`mktemp -d /tmp/PACKAGES_TO_INSTALL.XXXXX`
	for pkg in $PACKAGES_TO_INSTALL;
	do
		echo "Installing $pkg"
		mkdir -p $TMP_DIR|| \
			die "error while creating $TMP_DIR"
		tar zxpvf $pkg ./control.tar.gz -O|tar zxpvC $TMP_DIR ./control ./prerm || \
			die "error while unpacking control.tar from $pkg"
		PKG_NAME=$(awk '/Package:/{print $2; exit(0)}' $TMP_DIR/control)|| \
			die "error while parsing control from $pkg"
		if [ -z "$PKG_NAME" ]; then die "error: pkg name is empty in $pkg"; fi
		echo "Installing '$PKG_NAME' package..."
		FILE_LIST=$(tar zxpvf $pkg ./data.tar.gz -O|tar zxpvC $FSDIR|| \
			die "error while unpacking data.tar from $pkg")
		:> $TMP_DIR/$PKG_NAME.list
		for fso in $FILE_LIST;
		do
			fso=$(realpath -m "/$fso")
			fsoPATH="$FSDIR/$fso"
			if [ -f "$fsoPATH" -o -L "$fsoPATH" ]
			then
				echo $fso >> $TMP_DIR/$PKG_NAME.list
			fi
		done
		mv -f $TMP_DIR/control $TMP_DIR/$PKG_NAME.control|| \
			die "error while moving $TMP_DIR/control from $pkg"
		mv -f $TMP_DIR/prerm $TMP_DIR/$PKG_NAME.prerm|| \
			die "error while moving $TMP_DIR/prerm from $pkg"
		mv -f $TMP_DIR/* $FSDIR/usr/lib/opkg/info|| \
			die "error while moving opkg info for $pkg"
	done
	rm -rf "$TMP_DIR"
fi


>&2 echo "repacking squashfs..."
rm -f "$IMG.new"
mksquashfs "$FSDIR" "$IMG.new" -comp xz -b 256K -no-xattrs
