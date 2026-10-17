# E5 OpenWrt 刷机包 · 深度休眠版（e5-sleep）

容悦 E5（展锐 UMS9621）的 OpenWrt 一键刷机包：上游 [e5-linux](https://github.com/sprd-linux-devs/e5-linux) 从源码完整重建的系统，
加上[深度休眠内核](https://github.com/CharlesGool/e5-sleep-kernel)、系统化的信息屏功能和 LuCI 网页升级。**非官方修改版，只适用于 E5。**

*An unofficial one-click OpenWrt flash package for the Rongyue E5: the system rebuilt from upstream e5-linux, the
[deep sleep kernel](https://github.com/CharlesGool/e5-sleep-kernel), the info-screen extras built in, and updates from LuCI.*

## 下载

**当前版本 e5-sleep8**：[Openwrt_E5_Flasher_sleep8.zip](https://github.com/CharlesGool/e5-openwrt-flasher/releases/download/e5-sleep8/Openwrt_E5_Flasher_sleep8.zip)
（167 MB，[Release 页面](https://github.com/CharlesGool/e5-openwrt-flasher/releases/tag/e5-sleep8)）

SHA-256 `029bd2bc86a70eee276e57231c0f6fd18bf73acf4b980191738682da830c1d2e`

## 包里有什么

| | 说明 |
|---|---|
| 系统 | OpenWrt 25.12.5，上游 e5-linux `bb8775e`（2026-10-16：Wi-Fi / 基带 / 短信 / 信息屏修复）从源码构建：ModemManager 1.24.0-r930、WPA3（SAE）版 hostapd、BlueZ、信息屏 1ca4d58；镜像版本 `bb8775e+e5-sleep8` |
| 内核 | `6.18.54-e5-sleep8-charles`，补丁 0001–0009：挂起时 AP 深睡、芯片级休眠、电量计校准唤醒改为约 9 小时一次、USB 全关时插着线也能挂起（[e5-sleep-kernel](https://github.com/CharlesGool/e5-sleep-kernel)） |
| 网页升级 | LuCI「系统 → E5 系统升级」：上传本刷机包 zip，校验后直接升级（不再需要电脑）；「刷写新的固件」已停用，免得误刷通用镜像 |
| 升级保留 | 设置、密码、SSH 密钥、信息屏应用、用 apk 另装的软件包（同一 OpenWrt 版本时，如 OpenClash），以及流量统计、短信转发设置、蓝牙配对、计划任务等（各软件包登记的 keep.d 清单）；卸载过的应用（包括电话）不会被装回来 |
| 系统功能 | 音量键、侧键开关热点、功率监测、底部导航成为系统功能：设置在「高级 → 按键 / 界面与锁屏 / 充电」，功率监测在「详细信息」页；禁用 IPv6 在「高级 → 网络」 |
| 预装应用 | [热点省电](https://github.com/CharlesGool/e5-hotspot-saver) 3.0（熄屏深度休眠、CPU 关闭核心、USB「关闭（仅充电 / 不充电）」）、[网页版应用](https://github.com/CharlesGool/e5-webapps) 1.6 |
| 其他 | 去掉 PPPoE 拨号（`ppp` 本体保留）；内置 SFTP（openssh-sftp-server）；信息屏为独立分支（去掉在线更新，关于页写明原作者 Enceka 与修改版维护者 CharlesGool） |

详细说明见包内 [README.zh-CN.md](package/README.zh-CN.md)（English: [README.md](package/README.md)）。

## 用法

和官方刷机包相同：

- **新装**（Android 下，Magisk root，USB 调试）：解压后运行 `flash.cmd`（Windows）或 `./flash.sh`；不插 SD 卡、装到手机存储用 `flash.cmd --data`。
- **升级**（OpenWrt 运行中）：
  - e5-sleep8 起：LuCI「系统 → E5 系统升级」上传 zip → 等“已校验” → 开始升级 → 立即重启；
  - 或电脑上 `flash.cmd --update`（USB 连着）。
- **从 Android 切回 OpenWrt**：`flash.cmd --boot-openwrt`，或 Magisk 切回模块。

刷机有风险，请先备份，风险自负；与荣悦及设备、芯片厂商无关。

## 版本

| 版本 | 下载 | 说明 |
|---|---|---|
| **e5-sleep8** | [本仓库 Release](https://github.com/CharlesGool/e5-openwrt-flasher/releases/tag/e5-sleep8) | 网页升级；USB 关闭（不充电）与插线深度休眠；升级保留流量统计等用户数据；功率监测修正 |
| e5-sleep4 | [e5-sleep-kernel Release](https://github.com/CharlesGool/e5-sleep-kernel/releases/tag/e5-sleep4) | 官方 2026-10-13 包 + 内核 0001–0007（芯片级休眠） |
| e5-sleep2 | [e5-sleep-kernel Release](https://github.com/CharlesGool/e5-sleep-kernel/releases/tag/e5-sleep2) | 官方 2026-10-13 包 + 内核 0001–0005 |

（e5-sleep5–7 是 e5-sleep8 之前的中间版本，没有公开发布。）

## 自己做刷机包

需要 x86_64 Linux + Docker（arm64 用 qemu-user-static）。大致流程（e5-sleep8）：

1. **内核**：[e5-sleep-kernel](https://github.com/CharlesGool/e5-sleep-kernel) 的 `build/build-e5.sh sleep8 -e5-sleep8-charles 6`，
   再用 e5-linux `upstream/stage-root-modules.py` 生成 `root-modules.tar`。
2. **上游系统**：检出 e5-linux `bb8775e`（含子模块），打上 [upstream/e5-linux-bb8775e.patch](upstream/e5-linux-bb8775e.patch)
   （BlueZ 在 x86 主机上编、`E5_FEATURES` 接受 `-e5-sleepN` 内核、hostapd 的 SAE 源码改动做成包补丁、构建时可用镜像源和 apk 缓存），
   恢复 CI 引导输入（`tools/ci-inputs.py restore`），然后：

   ```sh
   bash openwrt/build-modemmanager.sh && bash openwrt/build-bluez.sh
   E5_FEATURES=1 E5_DOCKER=0 E5_IMAGE_MB=2048 E5_ROOT_MODULES=.../root-modules.tar E5_ROOT_MODULES_ONLY=1 \
     E5_STANDALONE=1 E5_DEVICE_FILES=0 [E5_WRT_MIRROR=https://mirrors.ustc.edu.cn/openwrt] bash openwrt/build-rootfs.sh
   ```

3. **后处理**：[build/make-rootfs-sleep8.sh](build/make-rootfs-sleep8.sh)：删 PPPoE / GRUB、加 SFTP；
   [patch-infoscreen-sleep5.py](build/patch-infoscreen-sleep5.py) 到 [sleep8](build/patch-infoscreen-sleep8.py) 依次改信息屏；
   [builtin-apps-sleep6.py](build/builtin-apps-sleep6.py) 把四个应用做成系统功能；[overlay/](overlay) 是加进系统的文件；预装应用；改 SIM 状态时间戳。
4. **启动镜像**：[build/repack-boot.py](build/repack-boot.py) 以官方 boot.img 为底，只换内核和 initramfs 里的模块。
5. **组装**：以官方刷机包为底，换 `files/boot.img`、`files/openwrt.ext4.gz`、`files/boot.json`、`files/VERSION`、`SHA256SUMS`，
   以及 [package/device-install-image.sh](package/device-install-image.sh)（升级时保留软件包和用户数据）。

[tests/](tests) 是在镜像副本里（chroot）跑的检查：设置归组、内置应用隐藏、IPv6 开关、卸载记录、网页升级接口等。

## 许可

脚本为 MIT；刷机包源自 e5-linux（MIT，Enceka），其中的 Linux 内核为 GPL-2.0。见 [LICENSE](LICENSE)。
