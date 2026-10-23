#!/usr/bin/env python3
"""The e5-sleep11 change to the info screen, on an offline root (or a live one: ROOT=/):

  api.uc clients(): hostapd's get_clients asks the Wi-Fi driver about every station
  (CMD_GET_STATION over the chip's command channel).  The screen's /status calls it at
  every poll -- every few seconds, every 5 s even with the screen dark -- about one
  query a second with five phones on the hotspot.  The SC2355 firmware stalls under a
  busy command channel (the 2026-10-23 assert: CMD_GET_STATION, CMD_RSP_TIMEOUT_ERROR).
  The stations are now kept WIFI_TTL s, asked again sooner when the set of hostapd
  objects changes (the hotspot on or off) or a DHCP lease is written (a new client).

  patch-infoscreen-sleep11.py ROOT
"""
import sys

ROOT = sys.argv[1].rstrip('/')
p = ROOT + '/usr/share/e5-infoscreen/api.uc'
s = open(p, encoding='utf-8').read()


def once(a, b):
    global s
    assert s.count(a) == 1, a[:60]
    s = s.replace(a, b)


if 'WIFI_TTL' in s:
    print('api.uc: already patched (stations cached)')
    sys.exit(0)

once("const MODEM_TTL = 10;                        // seconds\n",
     "const MODEM_TTL = 10;                        // seconds\n"
     "const WIFI_TTL = 20;                         // seconds: hostapd's stations (each a driver query)\n")

once("""	let wifi = {};
	if (!bus)
		bus = connect();
	for (let obj in (bus?.list() ?? [])) {
		if (substr(obj, 0, 8) != 'hostapd.')
			continue;
		for (let mac, st in (ubus_call(obj, 'get_clients')?.clients ?? {}))
			if (st.assoc)
				wifi[lc(mac)] = st.signal;
	}
""", """	// (e5-sleep11) get_clients asks the driver about every station (CMD_GET_STATION
	// on the chip's command channel, which its firmware stalls on when busy): kept
	// WIFI_TTL s; asked again when the hostapd objects change or a lease is written
	if (!bus)
		bus = connect();
	let objs = filter(bus?.list() ?? [], (o) => substr(o, 0, 8) == 'hostapd.');
	let key = join(' ', objs) + ' ' + (stat('/tmp/dhcp.leases')?.mtime ?? 0);
	let cached = length(objs) ? state_get('wifi-stations', WIFI_TTL) : null;
	let wifi = (cached && cached.key == key) ? cached.wifi : null;
	if (wifi == null) {
		wifi = {};
		for (let obj in objs)
			for (let mac, st in (ubus_call(obj, 'get_clients')?.clients ?? {}))
				if (st.assoc)
					wifi[lc(mac)] = st.signal;
		if (length(objs))
			state_put('wifi-stations', { key, wifi });
	}
""")
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('api.uc: hostapd stations cached %ss' % 20)
