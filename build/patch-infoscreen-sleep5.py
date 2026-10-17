#!/usr/bin/env python3
"""The e5-sleep5 changes to the info screen, on an offline root (make-rootfs-sleep5.sh):

  * 禁用 IPv6 built in: three switches in 高级 -> 网络 over /usr/libexec/e5-ipv6
    (it was the noipv6 app; the same uci config e5-plugin-noipv6);
  * no online update: the screen is this firmware's own branch -- no check, no
    update card, no 检查更新 / 回退 in 高级 -> 系统, no upload in LuCI;
  * 关于: Enceka as the original author, CharlesGool as the fork's maintainer,
    and a QR code of github.com/CharlesGool under 赞赏.

Every anchor must be there exactly once; hotspotdata's (const system_cat,
const cpu_categories, const about) are left as they are.

    patch-infoscreen-sleep5.py ROOT
"""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])


def once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{what}: anchor found {n} times')
    return text.replace(old, new)


def cut(text, start, end, what):
    """text without [start, end) -- end itself stays."""
    if text.count(start) != 1 or text.count(end) != 1:
        raise SystemExit(f'{what}: anchors not found exactly once')
    a, b = text.index(start), text.index(end)
    if a >= b:
        raise SystemExit(f'{what}: anchors out of order')
    return text[:a] + text[b:]


# ---------- settings.uc ----------
p = root / 'usr/share/e5-infoscreen/settings.uc'
s = p.read_text()

IPV6 = r"""/* ---------- e5-sleep5: 禁用 IPv6, built in (/usr/libexec/e5-ipv6; it was the noipv6 app) ---------- */
const IPV6_CFG = 'e5-plugin-noipv6';
const IPV6_KEYS = { ipv6_off: 'enabled', ipv6_wan4: 'wan_ipv4', ipv6_aaaa: 'filter_aaaa' };
function ipv6_items() {
    let c = ctx.uci(), on = (k) => (c.get(IPV6_CFG,'settings',k) ?? '1') != '0';
    let fx = ctx.sh_json('/usr/libexec/e5-ipv6 status') ?? {};
    let state = fx.applied ? L('已禁用','Off') : L('已启用','On');
    let v6 = +fx.global_v6 || 0;
    return [
        {id:'ipv6_off',type:'toggle',label:L('禁用 IPv6','Disable IPv6'),value:on('enabled'),confirm:true,reload:true,
         note:L(`当前：IPv6 ${state.zh}，公网 IPv6 地址 ${v6} 个。移动网络、热点和 USB 都只用 IPv4；关闭后恢复成禁用前的设置，网络会重连几秒`,
                `Now: IPv6 ${state.en}, ${v6} global IPv6 addresses.  Mobile data, hotspot and USB on IPv4 only; off: the settings as they were, the network reconnects for a few seconds`)},
        {id:'ipv6_wan4',type:'toggle',label:L('移动网络只申请 IPv4','Mobile data asks for IPv4 only'),value:on('wan_ipv4'),confirm:true,reload:true,
         note:L('禁用 IPv6 时生效；改动时移动数据会重连一次，若上不了网可关掉这一项','With IPv6 off; data reconnects once on a change, turn it off if data then fails')},
        {id:'ipv6_aaaa',type:'toggle',label:L('DNS 不返回 IPv6 地址','No IPv6 addresses from DNS'),value:on('filter_aaaa'),reload:true,
         note:L('禁用 IPv6 时生效；连接的设备不会再尝试 IPv6，打开网页更快','With IPv6 off; clients do not try IPv6 at all')}
    ];
}
function ipv6_set(id, value) {
    if (type(value) != 'bool') return 'on or off';
    ctx.run(`[ -f /etc/config/${IPV6_CFG} ] || touch /etc/config/${IPV6_CFG}`);
    let c = ctx.uci();
    if (c.get(IPV6_CFG,'settings') == null) c.set(IPV6_CFG,'settings','settings');
    c.set(IPV6_CFG,'settings',IPV6_KEYS[id],value ? '1' : '0');
    if (!c.commit(IPV6_CFG)) return 'Cannot save the IPv6 setting';
    ctx.run('(/usr/libexec/e5-ipv6 sync) </dev/null >/dev/null 2>&1 &');
    return null;
}

"""
s = once(s, "const network = {\n", IPV6 + "const network = {\n", 'settings.uc: network')
s = once(s, "{id:'reconnect',type:'action',label:L('重新连接网络','Reconnect'),confirm:true}\n        ];",
         "{id:'reconnect',type:'action',label:L('重新连接网络','Reconnect'),confirm:true},\n"
         "            ...ipv6_items()\n        ];", 'settings.uc: network items')
s = once(s, "    set:function(id,value,slot) {\n",
         "    set:function(id,value,slot) {\n"
         "        if (IPV6_KEYS[id] != null) return ipv6_set(id,value);\n", 'settings.uc: network set')

# 高级 -> 系统: no 检查更新, 更新到, 回退信息屏 (信息屏版本 stays)
s = cut(s, "\t\t\t{ id: 'update_check',", "\t\t\tcpu_link('cpu',", 'settings.uc: update items')

# 关于
s = once(s, "{ id: 'maintainer', type: 'info', label: L('维护者', 'Maintainer'), value: 'Enceka <enceka@yeah.net>' },",
         "{ id: 'maintainer', type: 'info', label: L('原作者', 'Original author'), value: 'Enceka <enceka@yeah.net>' },\n"
         "\t\t\t{ id: 'fork_maintainer', type: 'info', label: L('修改版维护者', 'Fork maintainer'), value: 'CharlesGool',\n"
         "\t\t\t  note: L('e5-sleep 修改版：深度休眠内核、刷机包和信息屏应用', 'The e5-sleep fork: the deep sleep kernel, the flash package and the apps') },",
         'settings.uc: maintainer')
m = re.search(r"\{ id: 'donate', type: 'image',.*?\},\n", s, re.S)
if not m or s.count("id: 'donate'") != 1:
    raise SystemExit('settings.uc: donate item')
s = s[:m.end()] + (
    "\t\t\t{ id: 'fork_github', type: 'image', label: L('修改版 GitHub', 'The fork on GitHub'), src: '/charles-github.png',\n"
    "\t\t\t  caption: L('扫码打开 github.com/CharlesGool', 'github.com/CharlesGool') },\n") + s[m.end():]
p.write_text(s)

# ---------- updates.uc: nothing to check, nothing to start ----------
p = root / 'usr/share/e5-infoscreen/updates.uc'
s = p.read_text()
s = once(s, "\ttry { latest = json(ctx.read_trim(`${RUN}/latest.json`) ?? 'null'); } catch (e) {}\n",
         "\t// (e5-sleep: the screen is this firmware's own; no release of it is offered)\n", 'updates.uc: latest')
s = once(s, "function start(action, version) {\n",
         "function start(action, version) {\n"
         "\tif (action != 'defer') return 'The info screen is part of this firmware (e5-sleep); it is not updated on its own';\n",
         'updates.uc: start')
s = once(s, "function auto_check() {\n", "function auto_check() {\n\treturn state();\n}\n\nfunction auto_check_upstream() {\n",
         'updates.uc: auto_check')
p.write_text(s)

# ---------- the update tool: version only ----------
p = root / 'usr/libexec/e5-infoscreen/update'
s = p.read_text()
s = once(s, 'case "${1:-}" in\n\tversion) current ;;',
         '# e5-sleep: the screen is this firmware\'s own branch; it is not updated on its own\n'
         'case "${1:-}" in fetch|apply|rollback|install)\n'
         '\tdie "The info screen is part of this firmware (e5-sleep); it is not updated on its own" ;; esac\n'
         'case "${1:-}" in\n\tversion) current ;;', 'update')
p.write_text(s)

# ---------- LuCI: no 更新信息屏 upload ----------
p = root / 'www/luci-static/resources/view/e5-infoscreen/apps.js'
s = p.read_text()
s, n = re.subn(r",\s*E\('div', \{ 'class': 'cbi-section' \}, \[\s*E\('h3', '更新信息屏'\),.*?'上传并更新…'\)\s*\]\)",
               '', s, flags=re.S)
if n != 1:
    raise SystemExit(f'apps.js: update section found {n} times')
p.write_text(s)

print('info screen: IPv6 in 网络, no online update, 关于 with the fork')
