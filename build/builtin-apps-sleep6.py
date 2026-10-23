#!/usr/bin/env python3
"""e5-sleep6: volkeys, sidekey, powermon and navbar built into the image, on an offline root.

    builtin-apps-sleep6.py ROOT volkeys-v1.4.tar.gz sidekey-v1.3.tar.gz powermon-v1.2.tar.gz navbar-v1.4.tar.gz

Each app goes to ROOT/usr/share/e5-infoscreen/www/plugins/<id> as a directory of its own (the screen's
"builtin": not removable), its /etc/e5-infoscreen/plugins/<id> paths repointed there.  Their settings
also go into the screen's own categories (manifest settings_into, merged by api.uc: patch-infoscreen-sleep6.py):
volume keys and side key into a new 按键, the bottom bar into 屏幕, the power monitor into 充电.

As the screen is not updated on its own any more, what the apps' backends would patch at the first boot
is patched here, exactly as they do it (so they find themselves current and restart nothing): app.js
(volkeys, sidekey), index.html (sidekey), mobile.js (navbar); and what they install is installed: the
powermon sampler (/etc/init.d/powermon, enabled) and LuCI page, navbar's LuCI tab.
/usr/share/e5-infoscreen/builtin-apps lists the ids (the plugin tool and the --update keep them built in).
"""
import io
import json
import os
import sys
import tarfile
from pathlib import Path

root = Path(sys.argv[1])
WWW = root / 'usr/share/e5-infoscreen/www'
PLUGINS = WWW / 'plugins'

# where each app's settings go, and the labels they get there (beside other apps' items)
GROUPS = {
    'volkeys': ('keys', {'step': {'zh': '音量键每按一次亮度变化', 'en': 'Brightness per volume key press'}}),
    'sidekey': ('keys', {
        'hold': {'zh': '侧键长按时间', 'en': 'Side key: hold for'},
        'dark': {'zh': '熄屏时也能用侧键开关热点', 'en': 'Side key: also with the screen dark'},
        'locked': {'zh': '按键锁定时也能用侧键开关热点', 'en': 'Side key: also with the keys locked'},
        'vibrate': {'zh': '侧键开关热点时震动', 'en': 'Side key: vibration'}}),
    'navbar': ('screen', {'mode': {'zh': '底部导航显示', 'en': 'Bottom bar shows'}}),
    'powermon': ('charge', {'interval': {'zh': '功率监测采样间隔', 'en': 'Power monitor: sample interval'}}),
}
KEYS_LABEL = {'zh': '按键', 'en': 'Keys'}


def once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{what}: anchor found {n} times')
    return text.replace(old, new)


def install(tarball):
    with tarfile.open(tarball) as t:
        members = t.getmembers()
        if any(m.issym() or m.islnk() or m.name.startswith('/') or '..' in m.name.split('/') for m in members):
            raise SystemExit(f'{tarball}: links or odd paths')
        top = {m.name.split('/')[0] for m in members}
        if len(top) != 1:
            raise SystemExit(f'{tarball}: not one top directory')
        app = top.pop()
        dest = PLUGINS / app
        if dest.is_symlink() or dest.exists():
            raise SystemExit(f'{dest} is already there')
        for m in members:
            rel = m.name.split('/', 1)[1] if '/' in m.name else ''
            p = dest / rel
            if m.isdir():
                p.mkdir(parents=True, exist_ok=True)
                os.chmod(p, 0o755)
            else:
                p.parent.mkdir(parents=True, exist_ok=True)
                data = t.extractfile(m).read()
                p.write_bytes(data)
                os.chmod(p, 0o755 if m.mode & 0o111 else 0o644)
    return app, dest


def repoint(app, dest):
    old, new = f'/etc/e5-infoscreen/plugins/{app}', f'/usr/share/e5-infoscreen/www/plugins/{app}'
    n = 0
    for p in dest.rglob('*'):
        if p.is_file() and p.suffix != '.ko':
            s = p.read_text(encoding='utf-8')
            if old in s:
                p.write_text(s.replace(old, new), encoding='utf-8')
                n += s.count(old)
    left = [str(p) for p in dest.rglob('*') if p.is_file() and p.suffix != '.ko'
            and '/etc/e5-infoscreen/plugins' in p.read_text(encoding='utf-8')]
    if left:
        raise SystemExit(f'{app}: still /etc/e5-infoscreen/plugins in {left}')
    return n


def group(app, dest):
    into, labels = GROUPS[app]
    mf = dest / 'manifest.json'
    m = json.loads(mf.read_text(encoding='utf-8'))
    assert m['id'] == app
    m['settings_into'] = into
    if into == 'keys':
        m['settings_into_label'] = KEYS_LABEL
    for d in m.get('settings', []):
        if d['id'] in labels:
            d['group_label'] = labels[d['id']]
    mf.write_text(json.dumps(m, ensure_ascii=False, indent='\t') + '\n', encoding='utf-8')
    return m['version']


apps = {}
for tb in sys.argv[2:]:
    app, dest = install(tb)
    if app not in GROUPS:
        raise SystemExit(f'{app}: not one of the four')
    apps[app] = (dest, repoint(app, dest), group(app, dest))
if set(apps) != set(GROUPS):
    raise SystemExit(f'want {sorted(GROUPS)}, got {sorted(apps)}')

# ---------- the screen's files, patched as the backends do it ----------
app_js = (WWW / 'app.js').read_text(encoding='utf-8')
# volkeys (backend ensure_patch): patch.js in before volumeKey, that one renamed volumeKeyOrig
want = (PLUGINS / 'volkeys/patch.js').read_text(encoding='utf-8')
parts = app_js.split('async function volumeKey(step) {')
if len(parts) != 2:
    raise SystemExit('app.js: no single volumeKey()')
app_js = parts[0] + want + 'async function volumeKeyOrig(step) {' + parts[1]
# sidekey (backend file_state): patch.js in before the key lock
want = (PLUGINS / 'sidekey/patch.js').read_text(encoding='utf-8')
app_js = once(app_js, '/* ---------- key lock ---------- */', want + '/* ---------- key lock ---------- */', 'app.js: key lock')
(WWW / 'app.js').write_text(app_js, encoding='utf-8')
# sidekey: early.html before power-menu.js (else mobile.js) in index.html
idx = (WWW / 'index.html').read_text(encoding='utf-8')
want = (PLUGINS / 'sidekey/early.html').read_text(encoding='utf-8')
# (sidekey 1.4: before power-menu.js, which takes every key but power and volume on a dark screen)
anchor = '<script src="power-menu.js"></script>' if '<script src="power-menu.js"></script>' in idx else '<script src="mobile.js"></script>'
idx = once(idx, anchor, want + anchor, 'index.html: ' + anchor)
(WWW / 'index.html').write_text(idx, encoding='utf-8')
# navbar (backend ensure_patch): patch.js before navigation(), two lines of it changed
js = (WWW / 'mobile.js').read_text(encoding='utf-8')
want = (PLUGINS / 'navbar/patch.js').read_text(encoding='utf-8')
js = once(js, '    function navigation() {', want + '    function navigation() {', 'mobile.js: navigation()')
js = once(js, '        const items = navDefaults.map((fallback, i) => {', '        let items = navDefaults.map((fallback, i) => {', 'mobile.js: items')
js = once(js, "        const key = items.join(',');",
          "        const navAll = e5NavbarAll();\n"
          "        if (navAll) items = [0, 1, 2, 3, 4, 5, 6, 7, 8];\n"
          "        document.body.classList.toggle('nav-all', navAll);\n"
          "        const key = items.join(',');", 'mobile.js: key')
(WWW / 'mobile.js').write_text(js, encoding='utf-8')

# ---------- what the backends install ----------
def put(src, dst, mode):
    dst = root / dst.lstrip('/')
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(src.read_bytes())
    os.chmod(dst, mode)

pm = PLUGINS / 'powermon'
put(pm / 'powermon.init', '/etc/init.d/powermon', 0o755)
put(pm / 'luci/index.js', '/www/luci-static/resources/view/powermon/index.js', 0o644)
put(pm / 'luci/menu.json', '/usr/share/luci/menu.d/luci-app-powermon.json', 0o644)
put(pm / 'luci/acl.json', '/usr/share/rpcd/acl.d/luci-app-powermon.json', 0o644)
start = [l for l in (pm / 'powermon.init').read_text().splitlines() if l.startswith('START=')][0].split('=')[1]
link = root / f'etc/rc.d/S{start}powermon'
if link.is_symlink() or link.exists():
    link.unlink()
link.symlink_to('../init.d/powermon')
nb = PLUGINS / 'navbar'
put(nb / 'luci/navigation.js', '/www/luci-static/resources/view/e5-navbar/navigation.js', 0o644)
put(nb / 'luci/menu.json', '/usr/share/luci/menu.d/luci-app-zz-e5-navbar.json', 0o644)

(root / 'usr/share/e5-infoscreen/builtin-apps').write_text(''.join(f'{a}\n' for a in sorted(apps)))
for a, (dest, n, v) in sorted(apps.items()):
    print(f'built in: {a} {v} -> {GROUPS[a][0]} ({n} paths repointed)')
print('patched: app.js (volkeys, sidekey), index.html (sidekey), mobile.js (navbar); installed: powermon sampler + LuCI, navbar LuCI')
