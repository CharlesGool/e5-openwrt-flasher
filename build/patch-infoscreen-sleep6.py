#!/usr/bin/env python3
"""The e5-sleep6 changes to the info screen, on an offline root, after patch-infoscreen-sleep5.py and
builtin-apps-sleep6.py:

  * api.uc: a built-in app whose manifest has settings_into gets its settings into that category of the
    screen's own (as <app>_<id> items, with the manifest's group_label where there is one); a category
    that is not there (按键) is made, after 屏幕.  The app's own category stays, for its detail view.
  * the plugin tool: the apps in /usr/share/e5-infoscreen/builtin-apps stay built in -- a copy of one
    under /etc/e5-infoscreen/plugins (an older system's, kept by an update) goes instead of the built-in
    directory, and none of them is installed or removed on its own.

    patch-infoscreen-sleep6.py ROOT
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])


def once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{what}: anchor found {n} times')
    return text.replace(old, new)


# ---------- api.uc ----------
p = root / 'usr/share/e5-infoscreen/api.uc'
s = p.read_text(encoding='utf-8')
s = once(s, "/* ---------- settings ---------- */\n\nlet settings_list = null;\n",
         "/* ---------- settings ---------- */\n\n"
         "// e5-sleep6: a built-in app's settings inside one of the screen's categories too (manifest\n"
         "// settings_into): its items as <app>_<id>, labelled group_label where the manifest has one\n"
         "function settings_merge(list, m) {\n"
         "\tlet host = null, at = length(list);\n"
         "\tfor (let i = 0; i < length(list); i++) {\n"
         "\t\tif (list[i].id == m.settings_into) host = list[i];\n"
         "\t\tif (list[i].id == 'screen') at = i + 1;\n"
         "\t}\n"
         "\tif (host == null) {\n"
         "\t\thost = { id: m.settings_into, label: m.settings_into_label ?? { zh: m.settings_into, en: m.settings_into },\n"
         "\t\t\titems: function() { return []; }, set: function() { return 'no such setting'; } };\n"
         "\t\tsplice(list, at, 0, host);\n"
         "\t}\n"
         "\tlet own = plugin_category(m), pre = m.id + '_', items0 = host.items, set0 = host.set, labels = {};\n"
         "\tfor (let d in m.settings)\n"
         "\t\tif (d.group_label) labels[d.id] = d.group_label;\n"
         "\thost.items = function() {\n"
         "\t\tlet out = items0 ? items0() : [];\n"
         "\t\tfor (let it in own.items())\n"
         "\t\t\tpush(out, { ...it, id: pre + it.id, label: labels[it.id] ?? it.label });\n"
         "\t\treturn out;\n"
         "\t};\n"
         "\thost.set = function(id, value, slot) {\n"
         "\t\tif (type(id) == 'string' && substr(id, 0, length(pre)) == pre)\n"
         "\t\t\treturn own.set(substr(id, length(pre)), value);\n"
         "\t\treturn set0 ? set0(id, value, slot) : 'no such setting';\n"
         "\t};\n"
         "}\n\n"
         "let settings_list = null;\n", 'api.uc: settings')
s = once(s, "\t\tfor (let m in plugin_manifests())\n"
            "\t\t\tif (length(m.settings ?? []))\n"
            "\t\t\t\tpush(settings_list, plugin_category(m));\n\t}\n",
         "\t\tfor (let m in plugin_manifests())\n"
         "\t\t\tif (length(m.settings ?? []))\n"
         "\t\t\t\tpush(settings_list, plugin_category(m));\n"
         "\t\tfor (let m in plugin_manifests())\n"
         "\t\t\tif (m.builtin && m.settings_into && length(m.settings ?? []))\n"
         "\t\t\t\tsettings_merge(settings_list, m);\n\t}\n", 'api.uc: plugin categories')
p.write_text(s, encoding='utf-8')

# ---------- the plugin tool ----------
p = root / 'usr/libexec/e5-infoscreen/plugin'
s = p.read_text(encoding='utf-8')
s = once(s, "valid_id() {",
         "# e5-sleep6: apps of the image that stay built in (no copy of their own under $USER_DIR)\n"
         "LOCKED=/usr/share/e5-infoscreen/builtin-apps\n"
         "locked() { [ -f \"$LOCKED\" ] && grep -qx \"$1\" \"$LOCKED\"; }\n"
         "valid_id() {", 'plugin: valid_id')
s = once(s, "\t\tid=$(basename \"$d\")\n\t\t# (a built-in directory of the same id gives way to the installed app)\n",
         "\t\tid=$(basename \"$d\")\n"
         "\t\t# (e5-sleep6: an older copy of a locked built-in app goes, its settings stay)\n"
         "\t\tif locked \"$id\" && [ -d \"$WWW/$id\" ] && [ ! -L \"$WWW/$id\" ]; then\n"
         "\t\t\trm -rf \"$d\"; logger -t e5-infoscreen \"$id: built in, the installed copy removed\"; continue\n"
         "\t\tfi\n"
         "\t\t# (a built-in directory of the same id gives way to the installed app)\n", 'plugin: link')
s = once(s, "\tvalid_id \"$id\" || die \"the manifest's id is not valid: $id\"\n",
         "\tvalid_id \"$id\" || die \"the manifest's id is not valid: $id\"\n"
         "\tlocked \"$id\" && die \"$id is built into this firmware (e5-sleep); its settings are under 高级\"\n",
         'plugin: install')
s = once(s, "do_remove() {\n\tid=${1:?id}\n\tvalid_id \"$id\" || die \"not a valid id: $id\"\n",
         "do_remove() {\n\tid=${1:?id}\n\tvalid_id \"$id\" || die \"not a valid id: $id\"\n"
         "\tlocked \"$id\" && die \"$id is built into this firmware (e5-sleep)\"\n", 'plugin: remove')
p.write_text(s, encoding='utf-8')

print('info screen: built-in apps settings in 按键 / 屏幕 / 充电; the plugin tool keeps them built in')
