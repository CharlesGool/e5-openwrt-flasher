#!/usr/bin/env python3
"""The e5-sleep7 changes to the info screen, on an offline root, after the sleep5 and sleep6 ones:

  * the four built-in apps (volkeys, sidekey, powermon, navbar) are part of the system, not apps: hidden
    from the apps page, the app manager and LuCI's app list (manifest "hidden"; GET /api/plugins and
    `plugin list` leave them out).  Their backends still run (the notification poll reads every manifest),
    their settings stay in 高级 -> 按键 / 屏幕 / 充电;
  * 功率监测 is a card of the 详细信息 page (after the device card), drawn by www/powermon-card.js from
    powermon's own data -- the copy of its page that was only reachable as an app.

    patch-infoscreen-sleep7.py ROOT     (www/powermon-card.js comes from sleep7-overlay/)
"""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
SH = root / 'usr/share/e5-infoscreen'
HIDDEN = ['navbar', 'powermon', 'sidekey', 'volkeys']


def once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{what}: anchor found {n} times')
    return text.replace(old, new)


# ---------- the manifests ----------
locked = (SH / 'builtin-apps').read_text().split()
if sorted(locked) != HIDDEN:
    raise SystemExit(f'builtin-apps: {locked}')
for a in HIDDEN:
    p = SH / 'www/plugins' / a / 'manifest.json'
    m = json.loads(p.read_text(encoding='utf-8'))
    m['hidden'] = True
    p.write_text(json.dumps(m, ensure_ascii=False, indent='\t') + '\n', encoding='utf-8')

# ---------- api.uc: the list the pages get ----------
p = SH / 'api.uc'
s = p.read_text(encoding='utf-8')
s = once(s, "\t\t\treturn reply_json(200, { api_version: API_VERSION, plugins: plugin_manifests() });",
         "\t\t\treturn reply_json(200, { api_version: API_VERSION, plugins: filter(plugin_manifests(), (m) => !m.hidden) });",
         'api.uc: /plugins')
p.write_text(s, encoding='utf-8')

# ---------- the plugin tool's list (LuCI) ----------
p = root / 'usr/libexec/e5-infoscreen/plugin'
s = p.read_text(encoding='utf-8')
s = once(s, "do_list() {\n\tfor d in \"$WWW\"/*; do\n\t\t[ -f \"$d/manifest.json\" ] || continue\n\t\tid=$(basename \"$d\")\n",
         "do_list() {\n\tfor d in \"$WWW\"/*; do\n\t\t[ -f \"$d/manifest.json\" ] || continue\n\t\tid=$(basename \"$d\")\n"
         "\t\t# (e5-sleep7: the built-in ones are part of the system, not apps)\n"
         "\t\tlocked \"$id\" && continue\n", 'plugin: list')
p.write_text(s, encoding='utf-8')

# ---------- 详细信息: the 功率监测 card ----------
p = SH / 'www/index.html'
s = p.read_text(encoding='utf-8')
CARD = ('\t\t<div class="card" id="pm-card">\n'
        '\t\t\t<div><span class="label sect" id="pm-title"></span></div>\n'
        '\t\t\t<div id="pm-now"></div>\n'
        '\t\t\t<div class="pm-row pm-sect"><span class="sub" id="pm-chart-title"></span><span id="pm-spans" class="pm-spans"></span></div>\n'
        '\t\t\t<canvas id="pm-chart"></canvas><div class="sub" id="pm-chart-note"></div>\n'
        '\t\t\t<canvas id="pm-level"></canvas><div class="sub" id="pm-level-note"></div>\n'
        '\t\t\t<div id="pm-charge" hidden></div>\n'
        '\t\t\t<div id="pm-avg"></div>\n'
        '\t\t\t<div class="sub pm-sect" id="pm-note"></div>\n'
        '\t\t</div>\n')
TEMPS = '\t\t<div class="card">\n\t\t\t<div class="lh"><span data-t="temperatures"></span></div>\n'
s = once(s, TEMPS, CARD + TEMPS, 'index.html: temperatures card')
s = once(s, '<script src="app.js"></script>\n', '<script src="app.js"></script>\n<script src="powermon-card.js"></script>\n',
         'index.html: app.js')
p.write_text(s, encoding='utf-8')
if not (SH / 'www/powermon-card.js').is_file():
    raise SystemExit('www/powermon-card.js missing (sleep7-overlay)')

print('info screen: the built-in apps hidden from the app lists; 功率监测 on the 详细信息 page')
