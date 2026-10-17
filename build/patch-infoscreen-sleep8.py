#!/usr/bin/env python3
"""The e5-sleep8 changes on an offline root, after the sleep5, sleep6 and sleep7 ones
(and sleep8-overlay/: E5 系统升级, the replaced /lib/upgrade/platform.sh):

  * e5-charge: block -- the charger held off whatever the level (hotspotdata 3.0's USB 关闭（不充电）);
  * 禁用 IPv6: one switch (the mobile bearer on IPv4 and no AAAA answers come with it);
  * the bottom bar's setting in 高级 -> 界面与锁屏 (the 外观 one), its LuCI page's ACL, its config made;
  * the bottom bar's active mark anchored to its button (it jumped on repeated taps);
  * apps removed on purpose stay removed: the plugin tool keeps /etc/e5-infoscreen/removed-apps.

    patch-infoscreen-sleep8.py ROOT
"""
import json
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
SH = root / 'usr/share/e5-infoscreen'


def once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{what}: anchor found {n} times')
    return text.replace(old, new)


def edit(path, pairs):
    s = path.read_text(encoding='utf-8')
    for old, new, what in pairs:
        s = once(s, old, new, what)
    path.write_text(s, encoding='utf-8')


# ---------- e5-charge: block ----------
edit(root / 'usr/libexec/e5-charge', [
    ("#   full_once  1: charge to 100 % once, then back to the limit (cleared here)\n",
     "#   full_once  1: charge to 100 % once, then back to the limit (cleared here)\n"
     "#   block      1: not charging at all, whatever the level (e5-sleep8: USB 关闭（不充电）)\n",
     'e5-charge: doc'),
    ("\tif [ \"$full_once\" = 1 ]; then\n\t\twant=0\n",
     "\tif [ \"$(cfg block 0)\" = 1 ]; then\n\t\twant=1          # (held off: the battery runs the device)\n"
     "\telif [ \"$full_once\" = 1 ]; then\n\t\twant=0\n",
     'e5-charge: decision'),
])

# ---------- 禁用 IPv6: one switch ----------
p = SH / 'settings.uc'
s = p.read_text(encoding='utf-8')
a = s.index("        {id:'ipv6_wan4',")
b = s.index("    ];\n}\nfunction ipv6_set(")
# (the first item's closing "},\n" becomes "}\n": the two after it go)
s = s[:a].rstrip(',\n') + '\n' + s[b:]
if "{id:'ipv6_wan4'" in s or "{id:'ipv6_aaaa'" in s:
    raise SystemExit('settings.uc: ipv6 sub-items still there')
p.write_text(s, encoding='utf-8')
edit(root / 'usr/libexec/e5-ipv6', [
    ('\t\tdo_on "$(setting wan_ipv4)" "$(setting filter_aaaa)"\n',
     '\t\t# (e5-sleep8: one switch -- the bearer on IPv4 and no AAAA answers come with it)\n\t\tdo_on 1 1\n',
     'e5-ipv6: sync'),
])

# ---------- the bottom bar: 界面与锁屏, its LuCI ACL, its config ----------
nb = SH / 'www/plugins/navbar'
m = json.loads((nb / 'manifest.json').read_text(encoding='utf-8'))
m['settings_into'] = 'ui'
m.pop('settings_into_label', None)
(nb / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent='\t') + '\n', encoding='utf-8')
acl = root / 'usr/share/rpcd/acl.d/luci-app-e5-navbar.json'
acl.write_bytes((nb / 'luci/acl.json').read_bytes())
os.chmod(acl, 0o644)
for f, dst in (('luci/menu.json', 'usr/share/luci/menu.d/luci-app-zz-e5-navbar.json'),
               ('luci/navigation.js', 'www/luci-static/resources/view/e5-navbar/navigation.js')):
    (root / dst).write_bytes((nb / f).read_bytes())
cfg = root / 'etc/config/e5-plugin-navbar'
if not cfg.exists():
    cfg.write_text("\nconfig settings 'settings'\n\toption mode 'all'\n")
    os.chmod(cfg, 0o644)

# ---------- the bottom bar's active mark ----------
p = SH / 'www/mobile.css'
s = p.read_text(encoding='utf-8')
s += ('\n/* e5-sleep8: the active mark on its own button (it was placed against the bar, where a button\'s\n'
      '   pressed state moved it: repeated taps made it jump) */\n'
      '#mobile-nav button { position:relative; }\n'
      '#mobile-nav button.active::after { left:50%; margin-left:-6px; bottom:3px; }\n')
p.write_text(s, encoding='utf-8')

# ---------- apps removed on purpose stay removed ----------
edit(root / 'usr/libexec/e5-infoscreen/plugin', [
    ("locked() { [ -f \"$LOCKED\" ] && grep -qx \"$1\" \"$LOCKED\"; }\n",
     "locked() { [ -f \"$LOCKED\" ] && grep -qx \"$1\" \"$LOCKED\"; }\n"
     "# e5-sleep8: apps removed on purpose, kept removed across image updates (the image's own ones too)\n"
     "REMOVED=/etc/e5-infoscreen/removed-apps\n"
     "removed() { [ -f \"$REMOVED\" ] && grep -qx \"$1\" \"$REMOVED\"; }\n"
     "mark_removed() { removed \"$1\" || { mkdir -p \"${REMOVED%/*}\"; echo \"$1\" >> \"$REMOVED\"; }; }\n"
     "unmark_removed() { [ -f \"$REMOVED\" ] && sed -i \"/^$1\\$/d\" \"$REMOVED\"; return 0; }\n",
     'plugin: removed list'),
    ("\t\t# (e5-sleep7: the built-in ones are part of the system, not apps)\n",
     "\t\tremoved \"$id\" && [ ! -L \"$d\" ] && continue\n"
     "\t\t# (e5-sleep7: the built-in ones are part of the system, not apps)\n",
     'plugin: list'),
    ("\t\t# (e5-sleep6: an older copy of a locked built-in app goes, its settings stay)\n",
     "\t\t# (e5-sleep8: one removed on purpose that an image update brought back goes again)\n"
     "\t\tif removed \"$id\" && ! locked \"$id\"; then rm -rf \"$d\" \"$WWW/$id\"; continue; fi\n"
     "\t\t# (e5-sleep6: an older copy of a locked built-in app goes, its settings stay)\n",
     'plugin: link'),
    ("\techo \"removed $id\"\n",
     "\tmark_removed \"$id\"\n\techo \"removed $id\"\n",
     'plugin: remove'),
])
p = root / 'usr/libexec/e5-infoscreen/plugin'
s = p.read_text(encoding='utf-8')
# the image's built-in directories of removed apps, at every link
s = once(s, "do_link() {\n\tmkdir -p \"$USER_DIR\" \"$WWW\"\n",
         "do_link() {\n\tmkdir -p \"$USER_DIR\" \"$WWW\"\n"
         "\tif [ -f \"$REMOVED\" ]; then\n"
         "\t\twhile read -r r; do\n"
         "\t\t\tvalid_id \"$r\" && ! locked \"$r\" && [ -d \"$WWW/$r\" ] && [ ! -L \"$WWW/$r\" ] && rm -rf \"$WWW/$r\"\n"
         "\t\tdone < \"$REMOVED\"\n"
         "\tfi\n", 'plugin: link removed built-ins')
# an install takes the app off the list
i = s.index('do_install() {')
j = s.index('\techo "installed $id', i)
s = s[:j] + '\tunmark_removed "$id"\n' + s[j:]
p.write_text(s, encoding='utf-8')

print('sleep8: e5-charge block, one IPv6 switch, the bottom bar in 界面与锁屏 (+ LuCI), its mark fixed, removed apps kept removed')
