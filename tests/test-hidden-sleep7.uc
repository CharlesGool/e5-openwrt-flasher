// e5-sleep7: the built-in apps hidden from the app lists, still running (run in a COPY of the image).
//     chroot ROOT ucode /tmp/test-hidden-sleep7.uc
'use strict';

import { readfile } from 'fs';

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
function req(method, path) {
	out = '';
	handle_request({ REQUEST_METHOD: method, PATH_INFO: path });
	let i = index(out, '\r\n\r\n');
	return { head: substr(out, 0, i), body: json(substr(out, i + 4)) };
}
const FOUR = ['navbar', 'powermon', 'sidekey', 'volkeys'];

let ids = map(req('GET', '/plugins').body.plugins, (m) => m.id);
check(!length(filter(ids, (i) => index(FOUR, i) >= 0)), `GET /plugins without the four: ${join(',', ids)}`);
check(index(ids, 'hotspotdata') >= 0 && index(ids, 'webapps') >= 0, 'GET /plugins keeps the installed apps');

let list = readfile('/tmp/plugin-list.txt') ?? '';
let listed = map(filter(split(list, '\n'), (l) => l != ''), (l) => split(l, '\t')[0]);
check(!length(filter(listed, (i) => index(FOUR, i) >= 0)) && index(listed, 'hotspotdata') >= 0,
	`plugin list (LuCI) without the four: ${join(',', listed)}`);

// their backends still answer (the pages' own routes and the notification poll)
let st = req('GET', '/plugins/powermon/status').body;
check(type(st) == 'object' && st.charts != null, 'GET /plugins/powermon/status answers (the card\'s data)');
let mode = req('GET', '/plugins/volkeys/mode').body;
check(mode?.mode != null, `GET /plugins/volkeys/mode answers (${mode?.mode})`);
check(type(req('GET', '/notifications').body?.notifications) == 'array', 'GET /notifications runs (it polls every backend)');

// settings still where sleep6 put them
let keys = map(req('GET', '/settings/keys').body.items, (it) => it.id);
check(length(keys) == 8, `按键 has its 8 items (${length(keys)})`);

// the card on the 详细信息 page
let html = readfile('/usr/share/e5-infoscreen/www/index.html');
check(length(split(html, 'id="pm-card"')) == 2 && length(split(html, '<script src="powermon-card.js"></script>')) == 2, 'index.html: the card and its script, once');
check(index(html, 'id="pm-card"') < index(html, 'data-t="temperatures"') && index(html, 'data-title="adv_info"') < index(html, 'id="pm-card"'),
	'the card is on the 详细信息 page, before the temperatures');
check(length(split(html, '<script src="app.js"></script>\n')) == 2, 'hotspotdata\'s anchor (app.js) still once');

print(failed ? `${failed} FAILED\n` : 'all passed\n');
exit(failed ? 1 : 0);
