// e5-sleep7: 功率监测 (the built-in powermon) as a card of the 详细信息 page (adv_info), after the device
// card: the newest sample, the use and the charge over 30 min / 6 h / 24 h, the charging, the averages by
// state over 24 h.  Its data is powermon's own (GET /api/plugins/powermon/status, the sampler under
// /etc/init.d/powermon); this only draws it, and only while the page is shown (every 10 s).  The full
// chart and the CSV stay on LuCI: 状态 -> 功率监测.  Loaded after app.js (its page, P, blank, lang).
'use strict';
(function() {
	const $ = (id) => document.getElementById(id);
	const T = (o) => (lang == 'zh' ? o.zh : o.en);
	const escp = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
	let st = null, loadError = null, lastLoad = 0, shown = false, spansLang = null;

	const css = document.createElement('style');
	css.textContent = `
#pm-card .pm-row { display: flex; flex-wrap: wrap; column-gap: 8px; justify-content: space-between; align-items: baseline; }
#pm-card .pm-row + .pm-row { margin-top: 4px; }
#pm-card .pm-big { font-size: calc(22px * var(--ui-scale, 1)); font-weight: bold; font-variant-numeric: tabular-nums; white-space: nowrap; }
#pm-card .pm-val { font-weight: bold; font-variant-numeric: tabular-nums; }
#pm-card .pm-warn { color: var(--fair, #f2c14b); } #pm-card .pm-good { color: var(--good, #4fd18b); }
#pm-card canvas { display: block; width: 100%; height: 100px; margin-top: 4px; }
#pm-card .pm-spans button { background: rgba(var(--button-rgb, 34,41,53), .9); color: var(--dim); border: 0; border-radius: 6px; font: inherit;
	font-size: calc(12px * var(--ui-scale, 1)); padding: 3px 8px; margin-left: 4px; }
#pm-card .pm-spans button.on { background: var(--accent); color: var(--bg, #000); }
body[data-theme=light] #pm-card .pm-spans button { background: rgba(var(--button-rgb, 222,230,238), .9); }
body[data-theme=light] #pm-card .pm-spans button.on { background: var(--accent); color: #fff; }
#pm-card .pm-sect { margin: 8px 0 3px; }`;
	document.head.appendChild(css);

	function stateName(x) {
		if (x.sleep) return T({ zh: '深度休眠', en: 'deep sleep' });
		return [x.screen ? T({ zh: '亮屏', en: 'lit' }) : T({ zh: '熄屏', en: 'dark' }),
			x.hotspot ? T({ zh: '热点开', en: 'hotspot on' }) : T({ zh: '热点关', en: 'hotspot off' }),
			x.saver ? T({ zh: '省电', en: 'saver' }) : null].filter(Boolean).join(' · ');
	}
	function minutes(m) {
		if (m == null) return '';
		if (m < 60) return m + T({ zh: ' 分钟', en: ' min' });
		return Math.floor(m / 60) + T({ zh: ' 小时 ', en: ' h ' }) + (m % 60) + T({ zh: ' 分', en: ' min' });
	}

	const SPANS = [[1800, { zh: '30 分钟', en: '30 min' }], [6 * 3600, { zh: '6 小时', en: '6 h' }], [24 * 3600, { zh: '24 小时', en: '24 h' }]];
	let span = 1800;
	try { span = +localStorage.getItem('powermon.span') || 1800; } catch (e) {}
	if (!SPANS.some(([s]) => s == span)) span = 1800;

	// the charts' colours: the theme's own where it has one, a light and a dark set otherwise
	function palette() {
		const cs = getComputedStyle(document.body), light = document.body.dataset.theme === 'light';
		const v = (n, d) => (cs.getPropertyValue(n) || '').trim() || d;
		return {
			text: v('--dim', '#8b95a5'), use: v('--poor', '#f0625a'),
			level: light ? '#1f6fc0' : '#5aa9f0', nap: light ? '#7a52c7' : '#a98cf0',
			grid: light ? 'rgba(80,100,122,.22)' : 'rgba(139,149,165,.25)',
			axis: light ? 'rgba(80,100,122,.6)' : 'rgba(139,149,165,.6)',
			plugged: light ? 'rgba(40,150,90,.16)' : 'rgba(79,209,139,.18)',
			asleep: light ? 'rgba(122,82,199,.16)' : 'rgba(150,110,230,.25)'
		};
	}
	let C = palette();

	// a chart's canvas and plot box (the same margins in both, so their times line up)
	const AX = { L: 40, R: 4, T: 5, B: 16, H: 100 };
	function frame(id) {
		const c = $(id), W = c.clientWidth || 300, dpr = window.devicePixelRatio || 1;
		c.width = W * dpr; c.height = AX.H * dpr;
		const g = c.getContext('2d');
		g.setTransform(dpr, 0, 0, dpr, 0, 0);
		g.clearRect(0, 0, W, AX.H);
		g.font = '10px "Noto Sans CJK SC", "DejaVu Sans", sans-serif';
		return { g, W, x0: AX.L, x1: W - AX.R, y0: AX.T, y1: AX.H - AX.B };
	}
	// plugged in (green) and asleep (purple) bands, value gridlines, the time axis
	function axes(f, c, X, Y, ticks, label) {
		const { g, x0, x1, y0, y1 } = f, gap = Math.max(150, c.width * 2.5);
		g.fillStyle = C.plugged;
		c.pts.forEach((p, i) => {
			if (!p[2]) return;
			const a = i && p[0] - c.pts[i - 1][0] <= gap ? c.pts[i - 1][0] : p[0] - c.width;
			g.fillRect(X(Math.max(c.from, a)), y0, Math.max(1, X(p[0]) - X(Math.max(c.from, a))), y1 - y0);
		});
		g.fillStyle = C.asleep;
		for (const [a, b] of c.naps) g.fillRect(X(a), y0, Math.max(1, X(b) - X(a)), y1 - y0);
		g.strokeStyle = C.grid; g.fillStyle = C.text; g.lineWidth = 1;
		g.textAlign = 'right'; g.textBaseline = 'middle';
		for (const v of ticks) {
			const y = Math.round(Y(v)) + .5;
			g.beginPath(); g.moveTo(x0, y); g.lineTo(x1, y); g.stroke();
			g.fillText(label(v), x0 - 4, Math.min(y1 - 4, Math.max(y0 + 4, y)));
		}
		const sp = c.to - c.from, fit = Math.max(2, Math.floor((x1 - x0) / 48));
		const step = [300, 600, 900, 1800, 3600, 7200, 10800, 21600].find((v) => sp / v <= fit) || 43200;
		const p2 = (n) => String(n).padStart(2, '0');
		g.textAlign = 'center'; g.textBaseline = 'top';
		for (let t = Math.ceil(c.from / step) * step; t <= c.to; t += step) {
			const x = Math.round(X(t)) + .5, d = new Date(t * 1000);
			g.beginPath(); g.moveTo(x, y0); g.lineTo(x, y1); g.stroke();
			const s = p2(d.getHours()) + ':' + p2(d.getMinutes()), w = g.measureText(s).width / 2;
			g.fillText(s, Math.min(x1 - w, Math.max(x0 + w, x)), y1 + 3);
		}
		g.strokeStyle = C.axis;
		g.beginPath(); g.moveTo(x0 + .5, y0); g.lineTo(x0 + .5, y1 + .5); g.lineTo(x1, y1 + .5); g.stroke();
	}
	function drawCharts() {
		const c = st?.charts?.[span];
		C = palette();
		document.querySelectorAll('#pm-spans button').forEach((b) => b.classList.toggle('on', +b.dataset.span == span));
		const pf = frame('pm-chart'), lf = frame('pm-level');
		if (!c || c.to - c.from < 60 || c.pts.length + c.naps.length < 2) {
			$('pm-chart-note').textContent = T({ zh: '数据不够：采样开始后过一会儿再看', en: 'Not enough data yet' });
			$('pm-level-note').textContent = '';
			return;
		}
		const X = (t) => pf.x0 + (t - c.from) / Math.max(1, c.to - c.from) * (pf.x1 - pf.x0);
		const gap = Math.max(150, c.width * 2.5);
		const used = c.pts.filter((p) => p[1] != null).map((p) => p[1])
			.concat(c.naps.filter((z) => z[2] != null).map((z) => z[2])).sort((a, b) => a - b);
		let top = Math.max(100, (used.length ? used[Math.floor(used.length * 0.98)] : 0) * 1.1);
		const step = [50, 100, 200, 250, 500, 1000, 2000].find((v) => top / v <= 3) || 5000;
		top = Math.ceil(top / step) * step;
		const Yp = (v) => pf.y1 - Math.max(0, Math.min(top, v)) / top * (pf.y1 - pf.y0);
		const ticks = [];
		for (let v = 0; v <= top; v += step) ticks.push(v);
		axes(pf, c, X, Yp, ticks, (v) => v >= 1000 ? (v / 1000) + ' W' : v + (v ? ' mW' : ''));
		const g = pf.g;
		g.lineWidth = 1.5; g.strokeStyle = C.nap;
		for (const [a, b, mw] of c.naps) {
			if (mw == null) continue;
			g.beginPath(); g.moveTo(X(a), Yp(mw)); g.lineTo(X(b), Yp(mw)); g.stroke();
		}
		g.strokeStyle = C.use;
		for (let i = 1; i < c.pts.length; i++) {
			const p = c.pts[i - 1], q = c.pts[i];
			if (p[1] == null || q[1] == null || p[2] || q[2] || q[0] - p[0] > gap) continue;
			g.beginPath(); g.moveTo(X(p[0]), Yp(p[1])); g.lineTo(X(q[0]), Yp(q[1])); g.stroke();
		}
		$('pm-chart-note').innerHTML = T({
			zh: `<span style="color:${C.use}">━</span> 耗电　<span style="color:${C.nap}">━</span> 休眠估算　绿底 插电　紫底 深度休眠`,
			en: `<span style="color:${C.use}">━</span> use　<span style="color:${C.nap}">━</span> asleep (est.)　green: plugged in　purple: deep sleep` });
		const v = c.pts.filter((p) => p[3] != null);
		if (!v.length) { $('pm-level-note').textContent = ''; return; }
		let lo = Math.floor(Math.min(...v.map((p) => p[3])) / 5) * 5, hi = Math.ceil(Math.max(...v.map((p) => p[3])) / 5) * 5;
		if (hi - lo < 10) hi = lo + 10;
		if (hi > 100) { lo -= hi - 100; hi = 100; }
		const Yl = (p) => lf.y1 - (p - lo) / (hi - lo) * (lf.y1 - lf.y0);
		axes(lf, c, X, Yl, (hi - lo) % 10 == 0 ? [lo, (lo + hi) / 2, hi] : [lo, hi], (p) => p + '%');
		lf.g.lineWidth = 1.5; lf.g.strokeStyle = C.level;
		lf.g.beginPath();
		v.forEach((p, i) => { if (i) lf.g.lineTo(X(p[0]), Yl(p[3])); else lf.g.moveTo(X(p[0]), Yl(p[3])); });
		lf.g.stroke();
		$('pm-level-note').innerHTML = T({
			zh: `<span style="color:${C.level}">━</span> 电量 ${v[0][3]}% → ${v[v.length - 1][3]}%`,
			en: `<span style="color:${C.level}">━</span> charge ${v[0][3]}% → ${v[v.length - 1][3]}%` });
	}
	function drawNow(x) {
		const v = `${x.ma} mA · ${(x.mv / 1000).toFixed(2)} V${x.battery != null ? ' · ' + x.battery + '%' : ''}`;
		let big, line;
		if (x.kind == 'charging') {
			big = `<span class="pm-big pm-good">${T({ zh: '充电 ', en: 'Charging ' })}${x.charge_mw} mW</span>`;
			line = T({ zh: '插电中：这是充进电池的功率，不是耗电', en: 'Plugged in: what goes into the battery, not the use' });
		} else if (x.kind == 'full') {
			big = `<span class="pm-big pm-good">${T({ zh: '已充满', en: 'Full' })}</span>`;
			line = T({ zh: '插电中：电池几乎没有电流进出，由充电器供电', en: 'Plugged in: the charger runs the device' });
		} else if (x.kind == 'drain') {
			big = `<span class="pm-big pm-warn">${x.mw} mW</span>`;
			line = `<span class="pm-warn">${T({ zh: '正在充电，但电池仍在放电：USB 口供电不足（如电脑的 500 mA 口）', en: 'Charging, yet the battery still drains: the USB port gives too little (a computer\'s 500 mA)' })}</span>`;
		} else {
			big = `<span class="pm-big">${x.mw} mW</span>`;
			line = escp(stateName(x));
			if (x.held) line += ' · ' + T({ zh: '插着电，未在充电（充电保护或已充满），由电池供电', en: 'plugged in, not charging (limit or full): on battery' });
		}
		const avg = st.avg5 == null ? '' : !x.plugged
			? T({ zh: '5 分钟平均 ', en: '5-min avg ' }) + st.avg5 + ' mW'
			: st.avg5 >= 0 ? T({ zh: '5 分钟平均充电 ', en: '5-min avg charging ' }) + st.avg5 + ' mW'
			: T({ zh: '5 分钟平均放电 ', en: '5-min avg drain ' }) + (-st.avg5) + ' mW';
		$('pm-now').innerHTML =
			`<div class="pm-row">${big}<span class="sub">${v}</span></div>` +
			`<div class="pm-row sub"><span>${line}</span><span>${avg}</span></div>`;
	}
	function drawCharge() {
		const s = st.session, el = $('pm-charge');
		if (!s) { el.hidden = true; return; }
		el.hidden = false;
		const head = s.mw == null
			? (s.active ? T({ zh: '本次插电（没有充进电）', en: 'Plugged in now (nothing charged)' }) : T({ zh: '上次插电（没有充进电）', en: 'Last plugged in (nothing charged)' }))
			: (s.active ? T({ zh: '本次充电', en: 'This charge' }) : T({ zh: '上次充电', en: 'Last charge' }));
		const rows = [[T({ zh: '插电时长', en: 'Plugged in' }), minutes(s.minutes)]];
		if (s.from != null && s.to != null) rows.push([T({ zh: '电量', en: 'Battery' }), `${s.from}% → ${s.to}%`]);
		if (s.mw != null) rows.push([T({ zh: '平均充电', en: 'Avg charging' }), `${s.mw} mW · ${s.ma} mA`]);
		if (s.pct_per_hour != null) rows.push([T({ zh: '充电速度', en: 'Rate' }), `${s.pct_per_hour}% / ${T({ zh: '小时', en: 'h' })}`]);
		if (s.full_minutes != null) rows.push([T({ zh: '预计充满', en: 'Full in' }), T({ zh: '约 ', en: 'about ' }) + minutes(s.full_minutes)]);
		el.innerHTML = `<div class="sub pm-sect">${head}</div>` +
			rows.map(([k, v]) => `<div class="pm-row"><span class="label">${escp(k)}</span><span class="pm-val">${escp(v)}</span></div>`).join('');
	}
	function draw() {
		$('pm-title').textContent = T({ zh: '功率监测', en: 'Power monitor' });
		if (!st) {
			$('pm-now').innerHTML = loadError
				? `<div class="sub pm-warn">${T({ zh: '读取失败：', en: 'Cannot load: ' })}${escp(loadError)}</div>`
				: `<div class="sub">${T({ zh: '读取中…', en: 'Loading…' })}</div>`;
			return;
		}
		if (!st.now) $('pm-now').innerHTML = `<div class="sub">${T({ zh: '还没有数据：后台定时采样，稍等片刻。', en: 'No data yet: sampled in the background.' })}</div>`;
		else drawNow(st.now);
		drawCharge();
		const rows = (st.avg ?? []).slice().sort((a, b) => (a.mw ?? -1) - (b.mw ?? -1)).map((a) =>
			`<div class="pm-row"><span class="label">${escp(stateName(a))}</span><span><span class="pm-val">${a.mw == null ? T({ zh: '待测', en: 'n/a' }) : a.mw + ' mW'}</span> <span class="sub">${a.minutes} ${T({ zh: '分钟', en: 'min' })}</span></span></div>`);
		$('pm-avg').innerHTML = `<div class="sub pm-sect">${T({ zh: '最近 24 小时耗电平均（不含插电）', en: 'Last 24 h use averages (unplugged)' })}</div>` +
			(rows.length ? rows.join('') : `<div class="sub">${T({ zh: '没有未插电的数据：拔掉 USB 线才能测出耗电。', en: 'No unplugged data: unplug USB to measure.' })}</div>`);
		$('pm-note').textContent = T({ zh: '完整曲线和导出：电脑浏览器打开 LuCI → 状态 → 功率监测。', en: 'Full chart and CSV: LuCI -> Status -> Power monitor.' }) +
			(st.service ? '' : T({ zh: '（后台采样未运行）', en: ' (the sampler is not running)' }));
		// (the buttons made once per language: a refresh does not replace one being pressed)
		if (spansLang != lang) {
			spansLang = lang;
			$('pm-chart-title').textContent = T({ zh: '耗电与电量', en: 'Use and charge' });
			$('pm-spans').innerHTML = SPANS.map(([s, l]) => `<button data-span="${s}">${escp(T(l))}</button>`).join('');
		}
		drawCharts();
	}
	async function load() {
		lastLoad = Date.now();
		try {
			const r = await fetch('/api/plugins/powermon/status', { cache: 'no-store' });
			if (!r.ok) throw new Error('HTTP ' + r.status);
			st = await r.json(); loadError = null;
		} catch (e) { loadError = e.message || String(e); }
		if (shown) draw();
	}

	$('pm-card').addEventListener('click', (ev) => {
		const s = +ev.target.dataset?.span;
		if (!s) return;
		span = s;
		try { localStorage.setItem('powermon.span', String(s)); } catch (e) {}
		drawCharts();
	});
	new MutationObserver(() => { if (shown && st) drawCharts(); })
		.observe(document.body, { attributes: true, attributeFilter: ['data-theme', 'data-accent'] });
	// only while the 详细信息 page is shown: drawn as it comes up, then every 10 s
	setInterval(() => {
		const now = typeof page !== 'undefined' && page === P.adv_info && !blank;
		if (now && !shown) { shown = true; draw(); load(); }
		else if (now && Date.now() - lastLoad >= 10000) load();
		else if (!now) shown = false;
	}, 1000);
})();
