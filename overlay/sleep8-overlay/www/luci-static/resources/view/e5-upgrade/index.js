'use strict';
'require view';
'require rpc';
'require ui';

// LuCI 系统 -> E5 系统升级 (e5-sleep8): an E5 flash package (.zip, the one for flash.py) uploaded
// to userdata, verified, and installed the way flash.py --update does it -- the boot image into
// boot_b, the root image with the configuration and the added packages kept -- by
// /usr/libexec/e5-upgrade on the device (rpcd object e5-upgrade).  A reboot starts the new system.

var declare = function(m) { return rpc.declare({ object: 'e5-upgrade', method: m }); };
var callPrepare = declare('prepare'), callCheck = declare('check'), callStart = declare('start'),
	callStatus = declare('status'), callClean = declare('clean'), callReboot = declare('reboot');

var STATES = {
	idle: '尚未上传刷机包',
	checking: '正在解压和校验刷机包…',
	checked: '刷机包已校验，可以开始升级',
	running: '正在升级，请勿断电、不要关闭本页…',
	done: '升级完成，重启后进入新系统',
	failed: '失败（见下方日志）'
};

return view.extend({
	load: function() {
		return L.resolveDefault(callStatus(), {});
	},

	render: function(st) {
		var self = this;
		this.nodes = {
			current: E('span', {}, st.current || '-'),
			kernel: E('span', {}, st.kernel || '-'),
			free: E('span', {}, st.free_mb != null ? st.free_mb + ' MB' : '-'),
			state: E('span', { 'style': 'font-weight:bold' }, '-'),
			version: E('div', { 'style': 'margin:.5em 0;word-break:break-all' }),
			log: E('pre', { 'style': 'max-height:22em;overflow:auto;white-space:pre-wrap;display:none' }),
			upload: E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, 'handleUpload') }, '选择刷机包并上传…'),
			start: E('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(this, 'handleStart') }, '开始升级'),
			reboot: E('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': ui.createHandlerFn(this, 'handleReboot') }, '立即重启'),
			clean: E('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, 'handleClean') }, '删除已上传的包')
		};
		var n = this.nodes;
		this.show(st);
		if (st.state == 'checking' || st.state == 'running')
			this.follow();

		return E([], [
			E('h2', 'E5 系统升级'),
			E('div', { 'class': 'cbi-map-descr' }, [
				'上传 E5 刷机包（.zip，和电脑上 flash.py 用的是同一个包），在这里直接升级：保留设置、已装的应用和用 apk 装的软件包，和 flash.py --update 相同。',
				E('br'),
				'「系统 → 备份/升级」里的「刷写新的固件」不适用于 E5（通用镜像会损坏系统），已经停用；配置备份仍可在那里做。'
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', '当前系统'),
				E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr' }, [E('td', { 'class': 'td left', 'width': '33%' }, '镜像版本'), E('td', { 'class': 'td left' }, n.current)]),
					E('tr', { 'class': 'tr' }, [E('td', { 'class': 'td left' }, '内核'), E('td', { 'class': 'td left' }, n.kernel)]),
					E('tr', { 'class': 'tr' }, [E('td', { 'class': 'td left' }, '可用空间（存放刷机包）'), E('td', { 'class': 'td left' }, n.free)])
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', '升级'),
				E('p', ['状态：', n.state]),
				n.version,
				E('div', { 'class': 'cbi-page-actions', 'style': 'text-align:left' }, [n.upload, ' ', n.start, ' ', n.reboot, ' ', n.clean]),
				n.log
			])
		]);
	},

	// the buttons and texts for a status
	show: function(st) {
		var n = this.nodes, s = st.state || 'idle';
		n.state.textContent = STATES[s] || s;
		if (st.current) n.current.textContent = st.current;
		if (st.free_mb != null) n.free.textContent = st.free_mb + ' MB';
		n.version.textContent = st.version ? ('刷机包：' + st.version) : '';
		n.log.textContent = st.log || '';
		n.log.style.display = st.log ? '' : 'none';
		n.log.scrollTop = n.log.scrollHeight;
		var busy = (s == 'checking' || s == 'running');
		n.upload.disabled = busy || s == 'done';
		n.start.style.display = s == 'checked' ? '' : 'none';
		n.reboot.style.display = s == 'done' ? '' : 'none';
		n.clean.style.display = (s == 'checked' || s == 'failed') ? '' : 'none';
	},

	// the status every 2 s while something runs
	follow: function() {
		var self = this;
		if (this.following) return;
		this.following = true;
		var tick = function() {
			L.resolveDefault(callStatus(), {}).then(function(st) {
				self.show(st);
				if (st.state == 'checking' || st.state == 'running')
					window.setTimeout(tick, 2000);
				else
					self.following = false;
			});
		};
		window.setTimeout(tick, 1000);
	},

	handleUpload: function() {
		var self = this;
		return callPrepare().then(function(p) {
			if (!p || !p.ok) throw new Error((p && p.error) || '无法准备上传');
			if (p.free_mb < 600)
				throw new Error('空间不足：需要约 600 MB，可用 ' + p.free_mb + ' MB');
			return ui.uploadFile(p.path).then(function() {
				return callCheck();
			}).then(function(r) {
				if (!r || !r.ok) throw new Error((r && r.error) || '校验未能开始');
				self.show({ state: 'checking' });
				self.follow();
			});
		}).catch(function(e) {
			if (e && e.message) ui.addNotification(null, E('p', e.message), 'danger');
		});
	},

	handleStart: function() {
		var self = this, v = this.nodes.version.textContent;
		ui.showModal('开始升级？', [
			E('p', '将写入新内核（boot_b）并安装新的系统镜像，设置、应用和另装的软件包会保留。升级中请勿断电；完成后重启进入新系统。'),
			E('p', { 'style': 'word-break:break-all' }, v),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, '取消'), ' ',
				E('button', { 'class': 'btn cbi-button-negative', 'click': function() {
					ui.hideModal();
					callStart().then(function(r) {
						if (!r || !r.ok) throw new Error((r && r.error) || '升级未能开始');
						self.show({ state: 'running', version: v.replace(/^刷机包：/, '') });
						self.follow();
					}).catch(function(e) { ui.addNotification(null, E('p', e.message), 'danger'); });
				} }, '开始升级')
			])
		]);
	},

	handleReboot: function() {
		return callReboot().then(function() {
			ui.showModal('正在重启', [
				E('p', { 'class': 'spinning' }, '设备正在重启进入新系统，约 1 分钟后重新连接，再打开本页查看版本。')
			]);
		});
	},

	handleClean: function() {
		var self = this;
		return callClean().then(function() { return callStatus(); }).then(function(st) { self.show(st || {}); });
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
