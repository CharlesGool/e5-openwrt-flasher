#!/bin/sh
# e5-sleep8's system changes, on a COPY of the image (it removes an app, writes uci):
#     chroot ROOT sh /tmp/test-sleep8.sh
failed=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; failed=$((failed + 1)); fi; }
P=/usr/libexec/e5-infoscreen/plugin
SH=/usr/share/e5-infoscreen

# 禁用 IPv6: one switch
check 'settings.uc: one IPv6 item' "grep -q \"id:'ipv6_off'\" $SH/settings.uc && ! grep -q \"id:'ipv6_wan4'\\|id:'ipv6_aaaa'\" $SH/settings.uc"
check 'e5-ipv6 sync: the bearer and DNS with it' "grep -q 'do_on 1 1' /usr/libexec/e5-ipv6"

# e5-charge: block
check 'e5-charge: block holds the charger off' "grep -q 'cfg block 0' /usr/libexec/e5-charge"
check 'hotspotdata 3.0 sees it (blockable)' "grep -q 'cfg block' /usr/libexec/e5-charge && sh /etc/e5-infoscreen/plugins/hotspotdata/usb-off.sh get | grep -q '\"nocharge_available\":true'"

# the bottom bar
check 'navbar: settings in 界面与锁屏' "jsonfilter -i $SH/www/plugins/navbar/manifest.json -e '@.settings_into' | grep -qx ui"
check 'navbar: its config made' "[ \"\$(uci -q get e5-plugin-navbar.settings.mode)\" = all ]"
check 'navbar: LuCI ACL and page' "[ -f /usr/share/rpcd/acl.d/luci-app-e5-navbar.json ] && grep -q 'uci.load' /www/luci-static/resources/view/e5-navbar/navigation.js && grep -q luci-app-e5-navbar /usr/share/luci/menu.d/luci-app-zz-e5-navbar.json"
check 'navbar: the bar rebuilt at once (patched mobile.js)' "grep -q 'e5NavbarRefresh' $SH/www/mobile.js"
check 'the active mark anchored to its button' "grep -q '#mobile-nav button { position:relative; }' $SH/www/mobile.css"

# powermon 1.3 and the card
check 'powermon 1.3: held, kept samples' "grep -q 'KEEP_CSV' $SH/www/plugins/powermon/service.sh && grep -q \"held: f\\[11\\]\" $SH/www/plugins/powermon/backend.uc"
check 'the card follows the theme' "grep -q 'function palette' $SH/www/powermon-card.js && grep -q 'x.held' $SH/www/powermon-card.js"

# apps removed on purpose stay removed
check 'phone installed to begin with' "$P list | grep -q '^phone	'"
$P remove phone >/dev/null 2>&1
check 'remove phone: listed as removed' "grep -qx phone /etc/e5-infoscreen/removed-apps"
# (an image update brings it back: the image's copies)
mkdir -p /etc/e5-infoscreen/plugins/phone && cp -a $SH/www/plugins/nettest/manifest.json /tmp/m.json
printf '{"id":"phone","api_version":2,"version":"1.5","name":"电话"}\n' > /etc/e5-infoscreen/plugins/phone/manifest.json
mkdir -p $SH/www/plugins/phone && cp /etc/e5-infoscreen/plugins/phone/manifest.json $SH/www/plugins/phone/
$P link
check 'link: the brought-back phone goes again' "[ ! -e /etc/e5-infoscreen/plugins/phone ] && [ ! -e $SH/www/plugins/phone ] && ! $P list | grep -q '^phone	'"
check 'a locked app cannot be removed' "! $P remove volkeys >/dev/null 2>&1 && ! grep -qx volkeys /etc/e5-infoscreen/removed-apps"

# E5 系统升级
check 'e5-upgrade status: JSON' "/usr/libexec/e5-upgrade status | jsonfilter -e '@.state' | grep -qx idle"
check 'e5-upgrade check without a package: refused' "/usr/libexec/e5-upgrade check | jsonfilter -e '@.ok' | grep -qx false"
check 'e5-upgrade start before a check: refused' "/usr/libexec/e5-upgrade start | jsonfilter -e '@.ok' | grep -qx false"
check 'LuCI: menu, ACL, view' "[ -f /usr/share/luci/menu.d/luci-app-e5-upgrade.json ] && [ -f /usr/share/rpcd/acl.d/luci-app-e5-upgrade.json ] && [ -f /www/luci-static/resources/view/e5-upgrade/index.js ]"
check 'generic sysupgrade refused' "! ( . /lib/upgrade/platform.sh; platform_check_image /dev/null >/dev/null )"

echo
[ "$failed" = 0 ] && echo 'all passed' || echo "$failed FAILED"
