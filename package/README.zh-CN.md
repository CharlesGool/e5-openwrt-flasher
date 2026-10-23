# OpenWrt 一键刷入包 · E5 深度休眠版（e5-sleep12）

> 这是**非官方修改版**，只适用于 **E5**。系统按上游 e5-linux `bb8775e`（2026-10-16，Wi-Fi / 基带 / 信息屏修复）从源码完整重建，
> 再加上深度休眠内核和下面的改动。刷入方法、要求、命令与原版完全相同（见下文）。
> e5-sleep8：内核 `-e5-sleep8-charles`（加补丁 0009：USB 全关时插着线也能深度休眠）；**LuCI「系统 → E5 系统升级」可以直接上传本刷机包升级**，不再需要电脑；音量键、侧键、功率监测、底部导航是系统功能（不是应用），功率监测在「详细信息」页。
> e5-sleep12：内核重新完整编译并改名为 `6.18.54-e5-sleep12-charles`（补丁 0001–0010，0010 不再单独替换模块），与刷机包版本一致；音量 − 关屏后**只在深度休眠期间**屏蔽其他按键（音量键 1.6 + 热点省电 3.4），没在休眠时（如热点开着）长按侧键照常开关热点；修复熄屏（含音量键关闭屏幕）时长按侧键没反应（侧键 1.4：排在上游电源键菜单的按键拦截之前）。
> e5-sleep11：减少触发 Wi-Fi 芯片崩溃的机会——信息屏不再每次刷新都向芯片查询已连接设备（缓存 20 秒，新设备连上立即更新），热点省电 3.3 也复用这份结果；实测查询从每分钟约 42 次降到约 2 次。
> e5-sleep10：**Wi-Fi 芯片崩溃后自动恢复**——芯片固件偶发断言复位后，热点以前会“开着但搜不到”直到重启；现在约 2 秒内自动重开（内核补丁 0010 修正驱动的恢复事件，恢复脚本连续崩溃时延后重试，热点省电 3.2 再兜底）。LuCI 网页升级进行中不会进入深度休眠。
> e5-sleep9：热点省电 3.1（没插 SIM 卡时也能关射频、进入深度休眠；系统装在 SD 卡上时暂不深度休眠，避免唤醒不了）；底部导航 1.6（9 个时「详细信息」显示为「详情」）。内核与 e5-sleep8 相同。

| 改动 | 说明 |
|---|---|
| 内核 `6.18.54-e5-sleep12-charles` | 官方 E5 构建流程（linux-lts-e5 020b970 + 上游 bb8775e 的显示 / eMMC DMA / EIC / 温度 / SIPA / 电量计 / Wi-Fi SAE 适配）加 9 个补丁：**USB 数据关闭时插着线也允许挂起**（0009，配合热点省电 3.0 的 USB「关闭（不充电）」），以及PMIC 看门狗挂起时停表、显示驱动挂起 WARNING、CPU 空闲状态、**挂起时关 GPU 电源域**、**相机电源域驱动**、**挂起时释放 USB PLL**（芯片级休眠）、USB 数据关闭时不轮询，以及 **电量计休眠校准唤醒改为约 9 小时一次**（原来每 2320 秒把设备唤醒一次；模块参数 `relax_cnt_threshold`，默认 8191，写 0 恢复设备树的 580） |
| `files/boot.img` | 以官方 boot.img 为底，只换内核和 initramfs 里的 45 个模块（init、busybox、f2fs 修复工具逐字节不变） |
| `files/openwrt.ext4.gz` | 上游 bb8775e 从源码构建（ModemManager 1.24.0-r930、WPA3/SAE 版 hostapd、BlueZ、信息屏 1ca4d58），只含新内核的模块；镜像版本显示为 `bb8775e+e5-sleep12` |
| 系统功能（sleep6 / sleep7） | **音量键 1.6、侧键 1.4、功率监测 1.4、底部导航 1.6 成为系统的一部分**：不出现在应用界面、应用管理和 LuCI 的应用列表里，不能卸载、不再单独安装；**功率监测在「详细信息」页**（设备卡片下面：当前功率、耗电与电量曲线 30 分钟 / 6 小时 / 24 小时、本次充电、24 小时各状态平均；随亮色 / 暗色主题配色；插着电但没在充电（充电保护停充、充满后停充）时按电池供电计入耗电，不再误报充电器供电不够；数据每 10 分钟存到 /etc/e5/powermon，重启和升级后保留；完整曲线和 CSV 仍在 LuCI「状态 → 功率监测」）；界面补丁在镜像里已打好（首次开机不再重启屏幕），功率监测的采样服务和 LuCI 页面预装。设置按功能放进「高级」：**按键**（新分类，在屏幕之后：长按侧键、侧键长按时间、熄屏 / 按键锁定时也能用侧键开关热点、震动；音量键、每按一次亮度变化、最低亮度再按音量 − 关闭屏幕）、**界面与锁屏**（底部导航显示：切换后导航栏立即重排；LuCI「服务 → 信息屏应用 → 底部导航」页可直接改 9 个 / 5 个）、**充电**（功率监测采样间隔） |
| 网页升级（sleep8） | **LuCI「系统 → E5 系统升级」**：上传 E5 刷机包（就是这个 .zip），自动解压、按 SHA256SUMS 校验、检查机型，再按 flash.py --update 的步骤升级（写 boot_b、换系统镜像，保留设置、应用和 apk 另装的软件包），完成后点「立即重启」。刷机包存在 userdata，不占内存；空间不够时会先提示，不会只写一半。「备份/升级」里的「刷写新的固件」已停用（通用镜像会损坏 E5），配置备份照常 |
| 充电与 USB（sleep8） | 充电保护新增强制停充；热点省电 3.0 的 USB 角色新增 **「关闭（不充电）」**：数据和充电都关，由电池供电，熄屏、关热点时插着线也能深度休眠 |
| 软件包 | **去掉 PPPoE 拨号**（ppp-mod-pppoe、luci-proto-ppp 等；`ppp` 本身保留，ModemManager 需要）和用不到的 GRUB EFI；**内置 SFTP**（openssh-sftp-server，WinSCP / FileZilla 直接用 SFTP 连） |
| 禁用 IPv6 | 原 noipv6 应用改为内置：**高级 → 网络** 最下面一个开关「禁用 IPv6」（同时让移动网络只申请 IPv4、DNS 不返回 IPv6），默认开，与原应用相同；从装有 noipv6 应用的系统升级时，原应用会被自动移除，设置保留 |
| 信息屏 | 本包的信息屏是独立分支：**去掉在线更新**（高级 → 系统 的检查更新 / 回退、概览的更新提示、LuCI 的上传更新）；**关于** 页写明原作者 Enceka 与修改版维护者 CharlesGool，赞赏下面加了修改版的 GitHub 二维码；SIM 状态时间戳改用 CLOCK_BOOTTIME |

这四个的来源与版本（已成为系统功能，设置在「高级」里）；预装的两个仍是应用，可在「应用管理」里升级或卸载：

| 应用 | 版本 | 形式 | 仓库 |
|---|---|---|---|
| 音量键（含 e5-sleep12 内核的 e5_keywake 模块） | 1.6 | 系统 | https://github.com/CharlesGool/e5-volkeys |
| 侧键开关热点 | 1.4 | 系统 | https://github.com/CharlesGool/e5-sidekey |
| 功率监测 | 1.4 | 系统（详细信息页） | https://github.com/CharlesGool/e5-powermon |
| 底部导航 | 1.6 | 系统 | https://github.com/CharlesGool/e5-navbar |
| 热点省电（熄屏深度休眠、CPU 关闭核心、USB 关闭（仅充电）、识别电量计校准唤醒、USB 关闭（不充电）、没插 SIM 卡也能休眠、Wi-Fi 卡死自动恢复） | 3.4 | 预装 | https://github.com/CharlesGool/e5-hotspot-saver |
| 网页应用 | 1.6 | 预装 | https://github.com/CharlesGool/e5-webapps |

内核补丁、构建方法和测试数据：https://github.com/CharlesGool/e5-sleep-kernel 。

刷入后可以这样确认电量计补丁生效：`cat /sys/module/ump96xx_fuel_gauge/parameters/relax_cnt_threshold` 读出 `8191`；
每次挂起的内核日志里有 `Sleep calib mode config done!!! (relax_cnt_th 8191)`。

注意：

* 这一版的用户态与 sleep4 差别较大（上游的 Wi-Fi、基带、短信、信息屏改动，上游说明这些改动未做完整构建和硬件耐久测试）；
  刷入后请重点检查热点、移动数据、短信和休眠。
* `--update` 升级会保留设备上已装的应用和它们的设置；包里带的应用（热点省电、网页版应用）比设备上已装的新时，换成包里的新版本，设置保留（e5-sleep9 起；以前的包是已装的旧版本覆盖包里的）。
  你卸载过的应用（包括电话）不会被升级装回来。这四个系统功能例外：旧系统里装的音量键、侧键、功率监测、底部导航在升级时被去掉，换成内置版，设置保留，不需要重装。
* `--update` 升级**保留用 apk 另装的软件包**（原版不保留）：新旧系统是同一个 OpenWrt 版本时，把这些包的文件、数据库记录、
  安装脚本、`/etc` 下它们独占的目录（如 OpenClash 的 `/etc/openclash`）和已启用的服务原样带到新系统；镜像自带而被你替换掉的包
  （如 `dnsmasq` 换成 `dnsmasq-full`）随之去掉；本包有意去掉的包（`/etc/e5/apk-removed.list`，即 PPPoE 和 GRUB）不会被带回来。
  版本不同时不搬运，包名记在 `/etc/e5/apk-carry.list`，升级后用 `apk add` 重装。
* 原版刷机包的 `--boot-openwrt` 会因 boot_b 哈希不同拒绝；从 Android 切回请用本包的 `--boot-openwrt` 或 Magisk 切回模块。
* 不要在 LuCI「系统 → 备份/升级」里刷固件：系统自带的 sysupgrade 是 armsr 通用版，不认识 E5 的存储布局。
* 本包为非官方修改，与荣悦及设备、芯片厂商无关。刷机有风险，请先备份，风险自负。

---

# OpenWrt 一键刷入包（E5 / T551M / VIPME M8）

> English: [`README.md`](README.md)

请使用与机型对应的包，不能跨机型刷入。包内 `files/device-profile.json` 标明目标机型；
安装和升级会检查机型。没有此文件的旧包仅适用于 E5。

把 OpenWrt 25.12（带 5G 上网、热点、LuCI 和屏幕信息屏）装到设备上，与原来的 Android
共存：Android 不动，OpenWrt 装到 **SD 卡**（独立分区，卡上其余空间保留）上，从 `boot_b` 启动。
随时可以回到 Android。加 `--data` 则装到手机存储里——即改用 SD 卡之前的做法。

## 需要

* 与安装包对应的设备，**bootloader 已解锁**，Android 已用 **Magisk** 获取 root；
* Android 在 slot a 运行（出厂状态就是）；
* 卡槽里插一张 **4 GB 以上的 SD 卡**（建议 8 GB）：它会被重新分区并清空，其余空间留给以后加分区。
  用 `--data` 则不需要卡，但要手机存储至少 2.5 GB 可用；
* 一台 Windows、macOS 或 Linux 电脑，装有：
  * **Python 3.8 或更新版本**（Windows 从 https://www.python.org/downloads/ 安装，勾选“Add python.exe to PATH”）；
  * **adb**（Android platform-tools：https://developer.android.com/tools/releases/platform-tools ，
    解压后把目录加入 PATH，或者把 `platform-tools` 文件夹放到刷机包目录里）；
  * Windows 还需要设备的 USB 驱动（多数情况下系统会自动安装）；
* USB 数据线。

## 刷入

1. 在设备上打开 USB 调试，用数据线连上电脑，在手机上允许调试；
2. 在 Magisk 里给 **Shell** 超级用户权限（第一次运行时手机会弹窗，选允许）；
3. 解压刷机包，在目录里运行：

   * **Windows**：双击 `flash.cmd`（或在命令提示符里运行 `flash.cmd`）；
   * **macOS / Linux**：`./flash.sh`

   想先确认设备没问题、什么都不写入，可以先运行 `flash.cmd --check` / `./flash.sh --check`。

   脚本会询问 APN、热点名称和密码。APN 直接回车即可：OpenWrt 会按 SIM 卡的运营商自动选择
   （移动 `cmnet`、联通 `3gnet`、电信 `ctnet`、广电 `cbnet`；其他运营商用网络默认的 APN），
   换卡后也会自动更新。密码直接回车会生成随机密码并在最后显示。也可以写在命令行里：

   ```sh
   flash.cmd --ssid E5-OpenWrt --wifi-key 12345678 -y        (Windows)
   ./flash.sh --ssid E5-OpenWrt --wifi-key 12345678 -y       (macOS / Linux)
   ```

   在分区、格式化 **SD 卡** 之前会再确认一次，需要输入 `yes`；输入别的或不回答都会中止，
   卡不会被改动。（`-y` 跳过所有询问。）

4. 等脚本显示“完成”，再手动重启进入 OpenWrt；安装器不自动重启，第一次启动约 2 分钟。

脚本做的事情：

* 检查刷机包完整性、设备状态（root、slot a、已解锁、启动控制块）和剩余空间；
  启动控制块按本机 BCAB 格式、CRC 和槽位状态检查，不再要求与打包设备逐字节相同。
* **从这台设备自己的 Android 里提取** Wi-Fi/蓝牙/音频固件和启动基带所需的 vendor 文件，打包成
  `/data/e5linux/device-files.tar`。刷机包里不带任何设备的固件：这些文件属于厂商，而且带有
  每台设备自己的信息（蓝牙地址、序列号），所以每台设备用自己的；
  固件提取、转换及镜像上传均在清卡之前完成，缺文件或上传失败不会先清卡。
* 检查两槽的 `uboot/sml/teecfg/trustos/vbmeta`。Android 释放 TF 后，对有差异的
  启动链先备份 A、B 两份至 `/data/adb/e5-bootchain/`，再从 A 同步到 B 并回读校验。
  相同项不重写；失败尝试恢复 B 原内容，任何失败都不会继续切槽。不会同步 NV。
* 给 **SD 卡** 分区（GPT，一个 Linux 分区）并把 OpenWrt 镜像写上去：这个分区**就是**根文件系统，
  initramfs 直接挂载它（卡上写有 `/etc/e5/sd-root` 标记）。分区只做到镜像大小，卡上其余空间保留，
  留给以后加更多系统或独立的存储分区；
* 把这台设备自己的文件解包进去，首次启动的设置写到它的 `/etc/e5/install.conf`；
  卸载、刷新缓存后以只读方式重新挂载，复核关键文件和固件 SHA-256，通过后才写 boot。
* 把启动镜像写入 `boot_b` 并校验，然后让下次启动走 slot b。**slot a 的 Android 不会被改动。**
  同时记录 userdata 上的 `e5linux/boot-os` 启动目标；最后备份本机 misc 的 32 字节
  启动控制信息、生成 B 槽试启动状态并回读校验。启动链备份也保存在 Android data 内；
* 加 `--data` 则改为把镜像写到 `/data/e5linux/openwrt.ext4`、设置写到
  `/data/e5linux/openwrt-install.conf`，并在写入前**确认三次**。

## 使用

### 安装到 userdata（无需 TF 卡）

Windows 双击 `install-userdata.cmd`，Linux/macOS 运行 `bash install-userdata.sh`。
也可以运行 `flash.cmd --data` / `bash flash.sh --data`。
脚本显示 `/data` 可用空间和镜像大小范围，让你输入 GiB 数值，例如 `4` 或 `6.5`。
镜像至少为包内根镜像大小（本批为 2 GiB），至少为 Android 保留 1 GiB，另计临时上传和固件空间。
命令行可指定 `install-userdata.cmd --image-size 4`；加 `-y` 且未指定大小时使用最小镜像。

此安装只创建 `/data/e5linux/openwrt.ext4` 文件，不格式化 userdata。
随包携带 ARM64/musl 的 ext4 扩容工具；先完整分配镜像空间，扩容、fsck、只读挂载检查，
通过后才同步 B 槽启动链和提交系统。旧镜像保存在 `/data/e5linux/previous.<时间>.<进程号>/`，
不自动删除，也不把它的空间算入可用空间。存在未完成 `.part` 或待提交 `.new` 时停止，请先检查。
安装完成后手动重启。首次安装会使用新的 OpenWrt 默认配置，旧镜像作为备份保留。

* 热点：用刷机时设置的名称和密码连接；或用 USB 线连接电脑（USB 网卡）。
* 管理页面 LuCI（中文、Aurora 主题）：`http://192.168.9.1`，用户 `root`，密码 `root`，**请尽快修改**
  （LuCI → 系统 → 管理权，或 SSH 里运行 `passwd`）。
* SSH：`ssh root@192.168.9.1`。
* 屏幕：左右键翻页，确认键按按钮，返回键返回；“高级”里有网络模式、频段、APN、充电控制等设置。

## 回到 Android

* 屏幕：高级 → 系统 → 下次启动 Android；
* 或 SSH 里：`e5-next-boot android && reboot`。

从 Android 再回到 OpenWrt（不重装，设置都在，之后默认启动也恢复为 OpenWrt）：连上电脑运行

```sh
flash.cmd --boot-openwrt          (Windows；macOS / Linux：./flash.sh --boot-openwrt)
```

如果 OpenWrt 启动失败，设备会在两次尝试后自动回到 Android。

`--boot-openwrt` 和 Magisk 切回模块也会先检查、同步启动链，再切槽重启。
本安装器仍要求 Android A、Linux B，不能在 Android B 下反向安装。
TF 仍采用预留更新空间的 GPT 布局，不采用占满第一分区的安装方式。

## 更新

安装失败时请保留完整终端报错：程序会显示失败的步骤（分区、写镜像、挂载、
解包设备文件或检查内容）、设备返回的错误和退出码，以及 SD/ext4 内核日志。
内容检查会列出缺失、空文件或没有执行权限的具体路径。分区前会检查卡容量和
只读状态；Android 卷无法卸载时会停止，尚未修改分区表。

设备正在运行 OpenWrt、用 USB 线连着电脑时，用新的刷机包运行：

```sh
flash.cmd --update                (Windows；macOS / Linux：./flash.sh --update)
```

它会通过 USB 网络更新启动镜像和 OpenWrt 镜像，**保留 OpenWrt 的设置**（`/etc/config`、密码、
SSH 密钥、流量记录、信息屏上装的应用）。用 `apk` 另装的软件包本版也会保留（见文首说明；原版不保留）。

**装在 SD 卡上**（默认方式）时，新系统写进卡上的第二个分区——第一次更新时在卡的空闲空间里建好，
以后轮流使用——旧系统照常运行，手机存储（userdata）完全不动。重启后启动新系统。新系统的第一次
启动是试运行：如果没能启动起来，下一次进入 Linux 时会回到之前的系统，设置保持原样（如果设备
已经自动回到了 Android，运行 `./flash.sh --boot-openwrt`）。更新需要卡上
有约一个镜像大小的空闲空间（1 GiB 多一点）。

装在手机存储里（`--data`）时，新镜像在重启后生效，旧镜像保留为
`/mnt/e5-data/e5linux/openwrt.ext4.old`。

## 卸载

回到 Android 后，在 root shell 里执行 `echo android > /data/e5linux/boot-os`（或删掉该文件），
这样卡不再是启动目标，然后把卡取出来，用任意分区工具清掉它的分区即可。用 `--data` 装的则要删
`/data/e5linux/openwrt.ext4`、`device-files.tar` 和 `openwrt-install.conf`。`boot_b` 里的启动
镜像留着也不影响 Android（Android 从 slot a 启动）。

## 免责声明

本刷机包为非官方软件，与荣悦及设备、芯片厂商无关，也未获其认可。刷机需要解锁 bootloader 和
root，可能导致设备失去保修、数据丢失或无法正常使用；修改网络、频段、AT 指令和充电设置也可能
导致断网或设备异常。本软件按“原样”提供，不作任何担保，**风险由使用者自行承担**。刷机前请备份
重要数据；所选频段和无线设置请遵守当地法规。

## 维护者与许可

Enceka <enceka@yeah.net>。脚本和 e5-linux 部分为 MIT 许可（见 `LICENSE`）；OpenWrt、Linux 内核
等组件遵循各自的许可（GPL 等），源码见 OpenWrt 官方和 e5-linux 仓库。
