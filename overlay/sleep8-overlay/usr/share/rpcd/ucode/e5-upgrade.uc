// E5 系统升级 for LuCI (系统 -> E5 系统升级, e5-sleep8): rpcd object "e5-upgrade" over
// /usr/libexec/e5-upgrade.  The package is the file LuCI's upload wrote (its path from prepare).
'use strict';

import { popen } from 'fs';

const TOOL = '/usr/libexec/e5-upgrade';

function run(arg) {
	let p = popen(`${TOOL} ${arg} 2>/dev/null`);
	let out = p ? p.read('all') : '';
	if (p) p.close();
	try { return json(out); }
	catch (e) { return { ok: false, error: trim(out ?? '') || 'e5-upgrade failed' }; }
}

return {
	'e5-upgrade': {
		prepare: { call: function() { return run('prepare'); } },
		check: { call: function() { return run('check'); } },
		start: { call: function() { return run('start'); } },
		status: { call: function() { return run('status'); } },
		clean: { call: function() { return run('clean'); } },
		reboot: {
			call: function() {
				system('(sleep 2; reboot) >/dev/null 2>&1 &');
				return { ok: true };
			}
		}
	}
};
