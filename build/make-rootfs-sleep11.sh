#!/bin/bash
# e5-sleep11 = e5-sleep10 with the screen asking hostapd for its stations once in 20 s, not at every
# poll (patch-infoscreen-sleep11.py: each is a driver query on the Wi-Fi chip's command channel), hotspotdata 3.3.
# e5-sleep10 = e5-sleep9 with the Wi-Fi driver of kernel patch 0010 (its firmware-reset uevent from the
# wiphy, so /etc/hotplug.d/ieee80211/90-sc2355-recovery runs), that script retrying instead of giving
# up on a second reset, no deep sleep during E5 系统升级 (sleep10-overlay/), hotspotdata 3.2.
# e5-sleep9 = e5-sleep8 with navbar 1.6 built in (详情 in the nine-item bar) and hotspotdata 3.1
# (no SIM counts as the radio off; no deep sleep with the system on the SD card).
# e5-sleep8 = e5-sleep7 on the e5-sleep8 kernel (0009: suspend with VBUS while USB data is off) with
# hotspotdata 3.0, powermon 1.3, navbar 1.5, volkeys 1.5, E5 系统升级 in LuCI (sleep8-overlay/) and
# patch-infoscreen-sleep8.py (e5-charge block, one IPv6 switch, the bottom bar in 界面与锁屏, removed apps).
# e5-sleep7 = e5-sleep6 with those four part of the system (hidden from the app lists) and 功率监测 a card
# of the 详细信息 page (sleep7-overlay/, patch-infoscreen-sleep7.py).
# e5-sleep6 = e5-sleep5 + volkeys, sidekey, powermon and navbar built in (builtin-apps-sleep6.py,
# patch-infoscreen-sleep6.py: their settings in 高级 -> 按键 / 屏幕 / 充电).
#
# Turn the generic image built from e5-linux bb8775e (openwrt/build-rootfs.sh with E5_FEATURES=1, the
# e5-sleep5 kernel's root modules) into the e5-sleep5 one:
#   - PPPoE and the armsr GRUB out, openssh-sftp-server in (/etc/e5/apk-removed.list for --update)
#   + 禁用 IPv6 built in (/usr/libexec/e5-ipv6, 高级 -> 网络), no online update of the info screen,
#     关于 with the fork (sleep5-overlay/, patch-infoscreen-sleep5.py)
#   + the info-screen apps in /etc/e5-infoscreen/plugins (what `plugin install` does)
#   + t551m-sim-status timestamps on CLOCK_BOOTTIME (they survive a suspend)
#   + image-version +e5-sleep5
set -euo pipefail
cd /root/e5/pkg
REL=6.18.54-e5-sleep8-charles-00072-g020b970e351e-dirty
SRC=${1:-/root/e5/up/out/openwrt/e5-openwrt-25.12.5-generic.ext4.gz}
gzip -dc "$SRC" > work.ext4
docker run --rm -v /root/e5/pkg:/p e5-mainline-build e2fsck -fn /p/work.ext4 >/dev/null
mkdir -p mnt
mount -o loop work.ext4 mnt
trap 'umount mnt 2>/dev/null || true' EXIT

# the kernel's root modules are the build's own: exactly this release
[ "$(ls mnt/lib/modules)" = "$REL" ]
echo "modules: $(find mnt/lib/modules/$REL -name '*.ko' | wc -l) in /lib/modules/$REL"
# WPA3: wifi-scripts writes unisoc_sae=1 for SAE; the daemon must know it (or the hotspot does not start)
grep -q unisoc_sae mnt/usr/share/ucode/wifi/hostapd.uc 2>/dev/null || grep -rqs unisoc_sae mnt/usr/share/ucode/wifi/ || \
    { echo "wifi-scripts without unisoc_sae"; exit 1; }
grep -aq unisoc_sae mnt/usr/sbin/wpad || { echo "wpad does not know unisoc_sae: rebuild openwrt/build-hostapd.sh"; exit 1; }
echo "WPA3: wifi-scripts and wpad both with unisoc_sae"

# packages: PPPoE and the generic armsr GRUB out (ppp itself stays: ModemManager depends on it; luci,
# luci-light and luci-ssl are empty meta packages that pull luci-proto-ppp), the SFTP server in (dropbear
# runs /usr/libexec/sftp-server).  /etc/e5/apk-removed.list keeps --update from carrying them back.
RM_PKGS="ppp-mod-pppoe kmod-pppoe kmod-pppox luci-proto-ppp luci luci-light luci-ssl grub2-efi-arm"
WRT_MIRROR=${E5_WRT_MIRROR-https://mirrors.ustc.edu.cn/openwrt}
docker run --rm --platform linux/arm64 -v /root/e5/pkg/mnt:/r -e RM_PKGS="$RM_PKGS" -e WRT_MIRROR="$WRT_MIRROR" \
    e5-openwrt-base:25.12.5 sh -euc '
# (the mirror only while adding; the image keeps the official feeds)
F=/r/etc/apk/repositories.d/distfeeds.list
cp $F /tmp/distfeeds.official
[ -z "$WRT_MIRROR" ] || sed -i "s#https://downloads.openwrt.org#$WRT_MIRROR#" $F
apk --root /r del $RM_PKGS
apk --root /r add openssh-sftp-server
cp /tmp/distfeeds.official $F
grep -q "^https://downloads.openwrt.org/" $F
for p in ppp modemmanager luci-proto-modemmanager luci-base luci-mod-network openssh-sftp-server; do
    apk --root /r info -e $p >/dev/null || { echo "missing $p"; exit 1; }
done
for p in $RM_PKGS; do ! apk --root /r info -e $p >/dev/null || { echo "still there: $p"; exit 1; }; done
[ -x /r/usr/libexec/sftp-server ]
'
printf '%s\n' $RM_PKGS > mnt/etc/e5/apk-removed.list
echo "packages: removed $RM_PKGS; added openssh-sftp-server; $(grep -c '^P:' mnt/lib/apk/db/installed) installed"

# the info screen: IPv6 built in, no online update, 关于
cp -a sleep5-overlay/. mnt/
chown -R 0:0 mnt/usr/libexec/e5-ipv6 mnt/etc/init.d/e5-ipv6 mnt/etc/hotplug.d/iface/90-e5-ipv6 \
    mnt/usr/share/e5-infoscreen/www/charles-github.png
chmod 755 mnt/usr/libexec/e5-ipv6 mnt/etc/init.d/e5-ipv6
chmod 644 mnt/etc/hotplug.d/iface/90-e5-ipv6 mnt/usr/share/e5-infoscreen/www/charles-github.png
ln -sf ../init.d/e5-ipv6 mnt/etc/rc.d/S99e5-ipv6
python3 patch-infoscreen-sleep5.py mnt
# e5-sleep6: the four apps built in, their settings into the screen's categories
python3 builtin-apps-sleep6.py mnt builtin9/volkeys-v1.5.tar.gz builtin9/sidekey-v1.3.tar.gz \
    builtin9/powermon-v1.4.tar.gz builtin9/navbar-v1.6.tar.gz
python3 patch-infoscreen-sleep6.py mnt
# e5-sleep7: the four hidden from the app lists, 功率监测 on the 详细信息 page
cp -a sleep7-overlay/. mnt/
python3 patch-infoscreen-sleep7.py mnt
# e5-sleep8
cp -a sleep8-overlay/. mnt/
chmod 755 mnt/usr/libexec/e5-upgrade
chmod 644 mnt/lib/upgrade/platform.sh mnt/usr/share/rpcd/ucode/e5-upgrade.uc mnt/usr/share/rpcd/acl.d/luci-app-e5-upgrade.json \
    mnt/usr/share/luci/menu.d/luci-app-e5-upgrade.json mnt/www/luci-static/resources/view/e5-upgrade/index.js
python3 patch-infoscreen-sleep8.py mnt
# e5-sleep10: the Wi-Fi driver with patch 0010, the recovery script that retries, the upgrade's wake lock
K=$(find mnt/lib/modules/$REL -name sprd_wlan_combo.ko)
[ -n "$K" ] && cmp -s "$K" /root/e5/dist-sleep8/modules/sprd_wlan_combo.ko || { echo "sprd_wlan_combo.ko in the image is not sleep8's"; exit 1; }
cp /root/e5/dist-sleep10/sprd_wlan_combo.ko "$K"
cmp -s "$K" /root/e5/dist-sleep10/sprd_wlan_combo.ko
echo "wifi: $K from patch 0010"
cp -a sleep10-overlay/. mnt/
chown -R 0:0 mnt/etc/hotplug.d/ieee80211/90-sc2355-recovery mnt/usr/libexec/e5-upgrade
chmod 755 mnt/etc/hotplug.d/ieee80211/90-sc2355-recovery mnt/usr/libexec/e5-upgrade
grep -q 'reopening in' mnt/etc/hotplug.d/ieee80211/90-sc2355-recovery && grep -q wake_hold mnt/usr/libexec/e5-upgrade
# e5-sleep11: the screen's Wi-Fi stations cached
python3 patch-infoscreen-sleep11.py mnt
grep -q WIFI_TTL mnt/usr/share/e5-infoscreen/api.uc
chown -R 0:0 mnt/lib/upgrade mnt/usr/libexec/e5-upgrade mnt/usr/share/rpcd mnt/usr/share/luci/menu.d \
    mnt/www/luci-static/resources/view mnt/etc/config/e5-plugin-navbar mnt/usr/share/e5-infoscreen
chown -R 0:0 mnt/usr/share/e5-infoscreen mnt/etc/init.d/powermon mnt/www/luci-static/resources/view \
    mnt/usr/share/luci/menu.d mnt/usr/share/rpcd/acl.d
chmod 644 mnt/usr/share/e5-infoscreen/www/powermon-card.js
docker run --rm --platform linux/arm64 -v /root/e5/pkg/mnt:/r e5-openwrt-base:25.12.5 sh -euc '
for f in /r/usr/share/e5-infoscreen/settings.uc /r/usr/share/e5-infoscreen/updates.uc \
         /r/usr/share/e5-infoscreen/www/plugins/*/backend.uc; do
    ucode -R -e "loadfile(\"$f\", { raw_mode: true }); print(\"compiles: $f\n\");"
done
# (api.uc is a template importing the system modules: compiled inside the image)
chroot /r ucode -e "loadfile(\"/usr/share/e5-infoscreen/api.uc\", { raw_mode: false }); print(\"compiles: api.uc\n\");"
sh -n /r/usr/libexec/e5-ipv6 && sh -n /r/usr/libexec/e5-infoscreen/update && sh -n /r/etc/init.d/e5-ipv6
sh -n /r/usr/libexec/e5-infoscreen/plugin && sh -n /r/etc/init.d/powermon
for f in volkeys/keywake.sh powermon/service.sh; do sh -n /r/usr/share/e5-infoscreen/www/plugins/$f; done
sh -n /r/usr/libexec/e5-upgrade && sh -n /r/lib/upgrade/platform.sh && sh -n /r/usr/libexec/e5-charge
ucode -R -e "loadfile(\"/r/usr/share/rpcd/ucode/e5-upgrade.uc\", { raw_mode: true }); print(\"compiles: e5-upgrade.uc\n\");"
'

# info-screen apps, as /usr/libexec/e5-infoscreen/plugin install does
U=mnt/etc/e5-infoscreen/plugins
W=mnt/usr/share/e5-infoscreen/www/plugins
for f in plugins11/*.tar.gz; do
	T=$(mktemp -d); tar -xzf "$f" -C "$T"
	[ -z "$(find "$T" -type l)" ] || { echo "$f has links"; exit 1; }
	src=$T; [ -f "$src/manifest.json" ] || src=$(dirname "$(ls "$T"/*/manifest.json)")
	id=$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); assert int(m["api_version"]) <= 2 and m["name"]; print(m["id"])' "$src/manifest.json")
	echo "$id" | grep -qE '^[a-z0-9][a-z0-9_-]{0,31}$'
	rm -rf "$U/$id"; cp -a "$src" "$U/$id"; chown -R 0:0 "$U/$id"; chmod -R u=rwX,go=rX "$U/$id"
	[ -d "$W/$id" ] && [ ! -L "$W/$id" ] && rm -rf "$W/$id"
	ln -sfn "/etc/e5-infoscreen/plugins/$id" "$W/$id"
	echo "app: $id $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$U/$id/manifest.json") ($(basename "$f"))"
	rm -rf "$T"
done
[ -f "$W/volkeys/keywake/$REL.ko" ] || { echo "volkeys has no e5_keywake for $REL"; exit 1; }
for a in noipv6 volkeys sidekey powermon navbar; do [ ! -e "$U/$a" ]; done
for a in volkeys sidekey powermon navbar; do [ -d "$W/$a" ] && [ ! -L "$W/$a" ]; done

# SIM status timestamps: CLOCK_BOOTTIME (the readers use /proc/uptime)
S=mnt/usr/libexec/t551m-sim-status
n=$(grep -c "'updated': time.monotonic()" $S)
[ "$n" = 2 ]
sed -i "s/'updated': time.monotonic()/'updated': time.clock_gettime(time.CLOCK_BOOTTIME)/" $S
echo "sim-status: $n timestamps on CLOCK_BOOTTIME"

# what the package says it is
# (bb8775e-dirty: only the two build scripts changed here, see build-rootfs.sh.e5-sleep5)
v=$(sed "s/-dirty$//" mnt/etc/e5/image-version); case "$v" in *+e5-sleep11) ;; *) echo "$v+e5-sleep11" > mnt/etc/e5/image-version ;; esac
echo "image-version: $(cat mnt/etc/e5/image-version), build-time $(cat mnt/etc/e5/build-time)"
printf '%s\n' "e5-sleep11 $(date -u +%FT%TZ): e5-linux bb8775e, kernel $REL, built in $(tr '\n' ' ' < mnt/usr/share/e5-infoscreen/builtin-apps), apps $(ls $U | tr '\n' ' ')" > mnt/etc/e5/e5-sleep11.release
sync; umount mnt; trap - EXIT
docker run --rm -v /root/e5/pkg:/p e5-mainline-build e2fsck -fn /p/work.ext4 | tail -1
gzip -9 -n -c work.ext4 > openwrt-sleep11.ext4.gz
sha256sum openwrt-sleep11.ext4.gz; ls -la openwrt-sleep11.ext4.gz
