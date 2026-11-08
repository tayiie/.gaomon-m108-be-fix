# GAOMON M108 笔侧键 B/E 误输入修复

> 不启动 GAOMON 驱动时，笔杆侧键会在原本的鼠标功能之外额外输入 `B`、`E`，导致聊天框/输入框出现错误字符。  
> 本仓库通过**在设备层禁用数位板的 HID 键盘接口**，在不影响笔尖、压感、鼠标左右键和音量键的前提下，彻底去掉 B/E。

[![Platform](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6?logo=windows)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell)](https://learn.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Tested on](https://img.shields.io/badge/tested-GAOMON%20M108-success)](#其他型号)

---

## 目录

- [问题](#问题)
- [根因](#根因)
- [方案](#方案)
- [快速开始](#快速开始)
- [验证](#验证)
- [恢复](#恢复)
- [会保留 / 会失效的功能](#会保留--会失效的功能)
- [其他型号](#其他型号)
- [常见问题](#常见问题)
- [技术细节](#技术细节)
- [免责声明](#免责声明)
- [License](#license)

---

## 问题

设备：**GAOMON M108**（内部型号 `GM001_T208`，USB `VID_256C / PID_0064`）。

现象：

- 不打开 GAOMON 驱动界面时，用笔杆上的两个侧键；
- 原有的鼠标功能（左键/右键）正常触发；
- 但会**额外**输入字母 `B` 和 `E`；
- 在记事本、聊天框、网页输入框里造成错误输入；
- 笔尖接触板面涂写时反而不出现，**悬停按住侧键时必现**。

## 根因

这块板子除了笔/鼠标接口，还暴露了一个**独立的 HID 键盘接口**：

```
HID\VID_256C&PID_0064&MI_02&Col04      HID Keyboard Device   (物理键盘集合)
HID\bigmax_hid_drv&Col07               HID Keyboard Device   (GAOMON 虚拟键盘)
```

GAOMON 后台驱动（`TabletDriver.exe` / `TabletServer.exe`）会读取键盘接口里的 `B`/`E`，然后用 **`PostMessage` / `SendMessage` 把这些按键消息直接投递到当前焦点窗口**。

这带来两个后果：

1. **低级键盘钩子（`WH_KEYBOARD_LL`）收不到这些按键**——它们不是走正常键盘输入链路，而是窗口消息注入；
2. 普通权限/管理员权限的按键拦截工具都拦不住，甚至 `Raw Input` 也只能在 HID 层看到原始报告，无法阻止注入。

因此，靠“按键钩子 + 过滤 B/E”的工具在这个场景下无效。唯一可靠的做法是**在设备层停掉那个键盘接口**。

> 详细分析（HID 集合表、报告格式、`ConfigFlags` 原理、为什么 `pnputil /disable-device` 会失败）见 [docs/technical.md](docs/technical.md)。

## 方案

脚本直接修改目标 HID 键盘集合的 `ConfigFlags`：

```
ConfigFlags = 0x1   (CONFIGFLAG_DISABLED)
```

然后调用 `pnputil /restart-device` 让设置立即生效。

为什么不用 `pnputil /disable-device`：

- Windows 把键盘类设备视为 **critical system device**，`pnputil` 会直接拒绝（`Cannot disable critical system device`）；
- 直接写 `ConfigFlags` 再重启设备，等同于设备管理器里的“禁用设备”，可以绕过这个限制。

脚本只匹配 **`kbdhid` / Keyboard** 的集合，不会动：

- 笔的 digitizer（`MI_01`）→ 压感、悬停、笔尖；
- 鼠标集合（`MI_02&Col01`）→ 左右键、光标；
- Consumer Control（`MI_02&Col05`）→ 音量/播放键。

## 快速开始

### 1. 获取

```powershell
git clone https://github.com/<your-name>/gaomon-m108-be-fix.git
cd gaomon-m108-be-fix
```

或者直接下载 ZIP 解压。

### 2. 禁用（去 B/E）

右键 **`scripts\disable-tablet-keyboard.cmd`** → **以管理员身份运行** → UAC 点“是”。

脚本会：

1. 枚举 `HKLM\SYSTEM\CurrentControlSet\Enum\HID` 下匹配的键盘集合；
2. 把 `ConfigFlags` 设为 `1`；
3. 用 `pnputil /restart-device` 重启设备；
4. 把每一步写进 `logs\fix-*.log`。

### 3. 测试

- 打开记事本，用笔侧键悬停按住：应**不再出现 B/E**；
- 笔尖涂写、压感、左右键、笔在板面上滑动滚页面：应正常；
- 音量键：正常。

## 验证

只读查看当前状态（不需要管理员）：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-TabletKeyboardState.ps1
```

输出示例：

```
State    ConfigFlags Service InstanceId
-----    ----------- ------- ----------
Disabled           1 kbdhid  HID\bigmax_hid_drv&Col07\1&...
Disabled           1 kbdhid  HID\VID_256C&PID_0064&MI_02&Col04\b&...
```

## 恢复

右键 **`scripts\enable-tablet-keyboard.cmd`** → **以管理员身份运行**。

它会把匹配集合的 `ConfigFlags` 改回 `0` 并重启设备。  
如果设备没有立即回来，拔插一次数位板或重启一次。

也可以手动指定：

```powershell
.\scripts\Disable-TabletKeyboard.ps1 -Undo
```

## 会保留 / 会失效的功能

| 功能 | 去 B/E 后 |
|---|---|
| 笔尖涂写、压感、悬停 | ✅ 保留 |
| 笔侧键的鼠标左/右键 | ✅ 保留 |
| 笔在板面上滑动滚页面 | ✅ 保留 |
| 音量键 | ✅ 保留 |
| 8 个多功能/快捷键 | ❌ 失效（同一个键盘接口） |
| 锁屏、截图等键盘快捷键 | ❌ 失效（同一个键盘接口） |
| B/E 误输入 | ✅ 消除 |

这是“彻底去 B/E”的代价：这些键和 B/E 共用同一个 HID 键盘接口，停掉接口就一起停了。

如果你更需要功能键，而不是原生笔行为，可以恢复键盘接口并保持官方驱动运行；两种模式按需切换即可。

## 其他型号

默认匹配：

```text
VID_256C&PID_0064      # GAOMON M108 / 同 VID/PID 的 HUION 设备
bigmax_hid_drv         # GAOMON 内核驱动创建的虚拟键盘
```

其他 GAOMON / HUION 型号：

1. 设备管理器 → 找到数位板下的 **HID Keyboard Device**；
2. 右键 → 属性 → 详细信息 → **设备实例路径**；
3. 记下其中的 `VID_xxxx&PID_xxxx`（以及是否有 `bigmax_hid_drv`）；
4. 传入 `-Match`：

```powershell
.\scripts\Disable-TabletKeyboard.ps1 -Match "VID_1234&PID_5678","bigmax_hid_drv"
```

更多说明见 [docs/compatibility.md](docs/compatibility.md)。

## 常见问题

### Q：脚本提示 `Cannot disable critical system device`？

那是 `pnputil /disable-device` 的限制。本脚本不调用它，而是直接写 `ConfigFlags` + 重启设备，不会遇到这个错误。

### Q：需要一直运行某个程序吗？

不需要。设置写在注册表设备键里，重启后仍然有效，没有常驻进程。

### Q：重装/升级驱动后 B/E 又回来了？

驱动安装/更新或换 USB 口会重新枚举设备，`ConfigFlags` 可能被重置。重新运行一次 `disable-tablet-keyboard.cmd` 即可。

### Q：功能键/锁屏/截图失效了？

这是停用键盘接口的预期结果。需要它们时运行 `enable-tablet-keyboard.cmd`，或打开官方驱动。

### Q：杀毒软件/安全软件提示？

脚本只做两件事：修改 `HKLM\SYSTEM\CurrentControlSet\Enum\HID\...` 下目标设备的 `ConfigFlags`，以及调用系统自带 `pnputil.exe` 重启设备。没有网络、没有常驻进程。可以审阅源码后再运行。

### Q：脚本报“拒绝访问”？

请确认是**以管理员身份**运行；UAC 被策略禁用时，需要从已提升的 PowerShell 窗口执行。

## 技术细节

- [docs/technical.md](docs/technical.md)：HID 集合、报告格式、`ConfigFlags`、注入原理、限制。
- [docs/compatibility.md](docs/compatibility.md)：兼容型号、如何找 VID/PID、`-Match` 用法。
- [CHANGELOG.md](CHANGELOG.md)：版本记录。

## 免责声明

本仓库通过修改 Windows 设备注册表键来禁用数位板的键盘接口。操作可逆（`enable-tablet-keyboard.cmd`），但仍建议：

- 运行前确认你知道要禁用哪些设备；
- 保留 `logs\fix-*.log`，便于排查；
- 在受控环境中先测试，再用于生产机器。

因使用本脚本造成的设备/系统问题，作者不承担责任。

## License

[MIT](LICENSE)
