// e5-sleep6: the settings API of a finished image, called as uhttpd would (run in a COPY of the
// image: it writes uci settings).    chroot ROOT ucode /tmp/test-settings-sleep6.uc
'use strict';

import { cursor } from 'uci';

let out = '', body = '';
global.uhttpd = {
	send: function(...a) { for (let x in a) out += x; },
	recv: function(n) { let b = body; body = ''; return b; },
	urldecode: function(s) { return s; }
};
loadfile('/usr/share/e5-infoscreen/api.uc', { raw_mode: false })();

let failed = 0;
function check(ok, what) {
	print(`${ok ? 'PASS' : 'FAIL'}: ${what}\n`);
	if (!ok) failed++;
}
function req(method, path, b) {
	out = '';
	body = b ? sprintf('%J', b) : '';
	handle_request({ REQUEST_METHOD: method, PATH_INFO: path, CONTENT_LENGTH: b ? `${length(body)}` : null });
	let i = index(out, '\r\n\r\n');
	return json(substr(out, i + 4));
}
function ids(items) { return map(items ?? [], (it) => it.id); }
function item(items, id) { for (let it in items ?? []) if (it.id == id) return it; return null; }

// the menu: 按键 right after 屏幕, the apps' own categories still there (hidden by the page)
let cats = req('GET', '/settings').categories;
let order = ids(cats);
let screen = index(order, 'screen'), keys = index(order, 'keys');
check(screen >= 0 && keys == screen + 1, `按键 after 屏幕 (${join(',', order)})`);
check(cats[keys]?.label?.zh == '按键' && !cats[keys]?.plugin && !cats[keys]?.parent, '按键 is a top-level category');
for (let a in ['volkeys', 'sidekey', 'powermon', 'navbar'])
	check(index(order, `plugin:${a}`) >= 0, `plugin:${a} still there (the app's detail view)`);

// 按键: the side key, then the volume keys (the apps' manifest order, 44 and 45)
let k = req('GET', '/settings/keys').items;
check(join(',', ids(k)) == 'sidekey_mode,sidekey_hold,sidekey_dark,sidekey_locked,sidekey_vibrate,volkeys_mode,volkeys_step,volkeys_off_at_min',
	`按键 items: ${join(',', ids(k))}`);
check(item(k, 'sidekey_hold')?.label?.zh == '侧键长按时间', 'group label: 侧键长按时间');
check(item(k, 'volkeys_mode')?.label?.zh == '音量键', 'own label kept where none given: 音量键');
let r = req('POST', '/settings/keys', { id: 'sidekey_hold', value: '1200' });
check(r.ok && r.item?.value == '1200', `POST 按键 sidekey_hold 1200 -> ${sprintf('%J', r.item?.value)}`);
check(cursor().get('e5-plugin-sidekey', 'settings', 'hold') == '1200', 'uci e5-plugin-sidekey.settings.hold = 1200');
r = req('POST', '/settings/keys', { id: 'volkeys_off_at_min', value: false });
check(r.ok && r.item?.value === false && cursor().get('e5-plugin-volkeys', 'settings', 'off_at_min') == '0', 'POST 按键 volkeys_off_at_min false');

// 屏幕 and 充电: their own items first, the app's after
// (e5-sleep8: the bottom bar's setting is in 界面与锁屏, category ui, where SLEEP8 is set)
let NAVCAT = getenv('SLEEP8') ? 'ui' : 'screen';
let s = req('GET', `/settings/${NAVCAT}`).items;
check(ids(s)[length(s) - 1] == 'navbar_mode', `${NAVCAT} has navbar_mode last (${length(s)} items)`);
if (NAVCAT == 'ui') check(index(ids(req('GET', '/settings/screen').items), 'navbar_mode') < 0, '屏幕 without navbar_mode');
r = req('POST', `/settings/${NAVCAT}`, { id: 'navbar_mode', value: 'five' });
check(r.ok && cursor().get('e5-plugin-navbar', 'settings', 'mode') == 'five', `POST ${NAVCAT} navbar_mode five`);
let c = req('GET', '/settings/charge').items;
check(index(ids(c), 'enabled') >= 0 && ids(c)[length(c) - 1] == 'powermon_interval', `充电 keeps its items, powermon_interval last (${length(c)} items)`);
check(item(c, 'powermon_interval')?.label?.zh == '功率监测采样间隔', 'group label: 功率监测采样间隔');
r = req('POST', '/settings/charge', { id: 'powermon_interval', value: '30' });
check(r.ok && cursor().get('e5-plugin-powermon', 'settings', 'interval') == '30', 'POST 充电 powermon_interval 30');
r = req('POST', '/settings/charge', { id: 'no_such', value: '1' });
check(!r.ok, `unknown id refused (${r.error})`);

// the app's own category, the same uci option
let p = req('GET', '/settings/plugin:sidekey').items;
check(item(p, 'hold')?.value == '1200', 'plugin:sidekey hold reads 1200 (same option)');

print(failed ? `${failed} FAILED\n` : 'all passed\n');
exit(failed ? 1 : 0);
