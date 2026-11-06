#!/usr/bin/env python3
"""The e5-sleep16 change to the info screen, on an offline root (or a live one: ROOT=/):

  Touch follows one finger by its identifier, not by the number of touches down.
  The tlsc6x panel can leave a contact pressed that it never releases (2026-11-06:
  `touch down id: 0` some 20 s after a charger was plugged in, no `touch up` for
  hours).  WebKit then lists that contact first in every TouchEvent.touches, so:
    mobile.js  the lock screen's swipe saw touches.length == 2 on every real
               finger and dropped it -- the screen could not be unlocked, which
               looked like dead touch until the UI was restarted;
    app.js     the page swipe read touches[0], the stuck contact, so it never moved.
  Both now start from the finger that went down (changedTouches) and keep its
  identifier; a contact that was already down is ignored.  On the lock screen a
  second finger still cancels a swipe that has moved; one that never moved (the
  stuck contact itself, if it went down in the swipe area) gives way to the new
  finger.  Tested on the device by injecting the stuck contact into event1.

  patch-infoscreen-sleep16.py ROOT
"""
import sys

ROOT = sys.argv[1].rstrip('/')
WWW = ROOT + '/usr/share/e5-infoscreen/www/'
s = ''


def once(a, b):
    global s
    assert s.count(a) == 1, a[:70]
    s = s.replace(a, b)


# ---- mobile.js: the lock screen swipe ----
p = WWW + 'mobile.js'
s = open(p, encoding='utf-8').read()
if 'gesture.id' in s:
    print('mobile.js: already patched (lock swipe by touch id)')
else:
    once("""            if (name.startsWith('touch')) {
                const point = event.touches[0] || event.changedTouches[0];
                if (name == 'touchcancel') resetGesture();
                else if (!point || (name == 'touchend' && event.touches.length)) resetGesture();
                else if (name == 'touchstart') start(point.clientX,point.clientY,event.touches.length);
                else if (name == 'touchmove') move(point.clientX,point.clientY,event.touches.length);
                else if (name == 'touchend') end(point.clientX,point.clientY);
            }""",
         """            if (name.startsWith('touch')) {
                // One finger, followed by its identifier: a contact the panel
                // never released stays in event.touches and must not count.
                const mine = list => gesture && [...list].find(t => t.identifier === gesture.id);
                if (name == 'touchcancel') resetGesture();
                else if (name == 'touchstart') {
                    // A finger that already moved is a real swipe: a second one
                    // cancels it.  One that never moved (the stuck contact) is
                    // replaced by the new finger.
                    const fresh = event.changedTouches;
                    if (fresh.length != 1 || gesture?.samples.length > 1) resetGesture();
                    else {
                        start(fresh[0].clientX,fresh[0].clientY,1);
                        if (gesture) gesture.id = fresh[0].identifier;
                    }
                } else if (name == 'touchmove') {
                    const point = mine(event.changedTouches);
                    if (point) move(point.clientX,point.clientY,1);
                } else if (name == 'touchend') {
                    const point = mine(event.changedTouches);
                    if (point) end(point.clientX,point.clientY);
                }
            }""")
    open(p, 'w', encoding='utf-8', newline='').write(s)
    print('mobile.js: lock swipe by touch id')

# ---- app.js: the page swipe ----
p = WWW + 'app.js'
s = open(p, encoding='utf-8').read()
if 'touch.id' in s:
    print('app.js: already patched (page swipe by touch id)')
else:
    once("""	resetIdle();
	const p = e.touches[0];
	touch = { x: p.clientX, y: p.clientY, t: Date.now() };
}, { capture: true, passive: false });""",
         """	resetIdle();
	// the finger that went down, not touches[0]: that can be a contact the
	// panel never released.  The newest finger is the swipe, as before.
	const p = e.changedTouches[0];
	touch = e.changedTouches.length != 1 ? null : { x: p.clientX, y: p.clientY, t: Date.now(), id: p.identifier };
}, { capture: true, passive: false });""")
    once("""	if (!touch) return;
	const p = e.changedTouches[0];
	const dx = p.clientX - touch.x, dy = p.clientY - touch.y;""",
         """	if (!touch) return;
	const p = [...e.changedTouches].find((t) => t.identifier === touch.id);
	if (!p) return;
	const dx = p.clientX - touch.x, dy = p.clientY - touch.y;""")
    open(p, 'w', encoding='utf-8', newline='').write(s)
    print('app.js: page swipe by touch id')
