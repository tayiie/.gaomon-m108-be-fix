# 技术细节

本文记录 GAOMON M108 上 B/E 误输入的定位过程、HID 结构、注入原理，以及为什么最终选择“设备层禁用键盘接口”。

## 1. 设备拓扑

GAOMON M108（`GM001_T208`）是一个 USB 复合设备：

```
USB\VID_256C&PID_0064
├── MI_00  HID  (vendor-defined collections)
├── MI_01  HID  (pen digitizer)
└── MI_02  HID  (mouse / vendor / multi-axis / keyboard / consumer)
```

`MI_02` 展开后的 HID 集合：

| 集合 | Usage | 用途 | 去 B/E 后 |
|---|---|---|---|
| `MI_02&Col01` | Generic Desktop / Mouse | 笔/鼠标移动、左右键 | 保留 |
| `MI_02&Col02` | Vendor `FF01:0000` | 厂商自定义 | 保留 |
| `MI_02&Col03` | Generic Desktop / Multi-axis | 圆盘（旋钮） | 保留 |
| `MI_02&Col04` | Generic Desktop / Keyboard | **B/E、功能键、锁屏/截图** | **禁用** |
| `MI_02&Col05` | Consumer / Consumer Control | 音量、播放/暂停、切歌 | 保留 |

另外，GAOMON 内核驱动会创建一个虚拟 HID 设备：

```
HID\bigmax_hid_drv&Col01..Col09
```

其中 `Col07` 也是 `HID Keyboard Device`（`kbdhid`），同样会承载 B/E；脚本一并禁用。

## 2. 观察到的报告

### 键盘集合（`Col04`）

标准 HID keyboard report。按下笔侧键会发送 `B`（0x05）或 `E`（0x08）的 keydown/keyup。

### Consumer Control（`Col05`）

3 字节报告，`06 XX 00`：

| 数据 | Usage | 含义 |
|---|---|---|
| `06 E9 00` | 0x0C:0xE9 | Volume Increment |
| `06 EA 00` | 0x0C:0xEA | Volume Decrement |
| `06 B6 00` | 0x0C:0xB6 | Scan Next Track |
| `06 B5 00` | 0x0C:0xB5 | Scan Previous Track |
| `06 CD 00` | 0x0C:0xCD | Play/Pause |

音量键走这里，所以禁用键盘集合不影响音量。

### Multi-axis（`Col03`，圆盘）

9 字节报告：

```
11 00 XX XX 00 00 00 00 00
```

- 第 1 字节：Report ID `0x11`
- 第 3-4 字节：小端有符号 `int16` 增量
- 实测：+1/+2/+3、-1/-2/-3/-4/-5，快速转动出现 ±21/±24
- 空闲时回 `11 00 00 00 ...`

这是圆盘的原始增量。圆盘的“滚轮/音量”模式、以及滚轮步长由 GAOMON 驱动/固件控制。

## 3. 为什么键盘钩子拦不住

正常的键盘输入路径：

```
HID -> hidclass -> kbdhid -> Raw Input Thread -> WH_KEYBOARD_LL -> 焦点窗口
```

`PostMessage` / `SendMessage` 注入的路径：

```
驱动 -> PostMessage(WM_KEYDOWN/WM_CHAR) -> 焦点窗口的消息队列
```

后者**不经过** Raw Input Thread，所以：

- `WH_KEYBOARD_LL` 不会收到回调；
- `WH_MOUSE_LL` 同理（圆盘滚轮也是驱动用 PostMessage 投递的）；
- 普通/管理员权限的钩子都无法拦截；
- `Raw Input` 能在 HID 层看到报告，但它只是“副本”，不能阻止驱动注入；
- UIPI 还会让低完整性进程看不到高完整性进程的注入消息。

实测日志：Raw Input 能看到 `MI_02&Col03` 的圆盘报告和 `MI_02&Col04` 的键盘报告，但 `WH_KEYBOARD_LL` 的日志里**没有任何 B/E 事件**——这就是“钩子工具无效”的直接证据。

## 4. ConfigFlags 与 critical device

每个 PnP 设备在注册表里有一个 `ConfigFlags`：

```
HKLM\SYSTEM\CurrentControlSet\Enum\<Bus>\<InstanceId>
```

`CONFIGFLAG_DISABLED = 0x00000001`。

`pnputil /disable-device` 最终调用 `CM_Disable_DevNode`，后者对键盘类设备会返回：

```
Cannot disable critical system device.
```

这是一个**策略检查**，发生在 API 层。直接写 `ConfigFlags = 1` 再重启设备，可以绕过该检查，效果等同于设备管理器里的“禁用设备”：

1. `Set-ItemProperty ... -Name ConfigFlags -Value 1 -Type DWord`
2. `pnputil /restart-device "<InstanceId>"`
3. PnP 重新启动设备时读取 `ConfigFlags`，发现 disabled，不再启动该集合。

恢复时把 `ConfigFlags` 设回 `0`，再重启设备。

## 5. 脚本逻辑

`scripts/Disable-TabletKeyboard.ps1`：

1. 检查管理员权限；不是管理员则用 `Start-Process -Verb RunAs` 自提升；
2. 枚举 `HKLM\SYSTEM\CurrentControlSet\Enum\HID` 下所有子键；
3. 只保留 `Service = kbdhid` 或 `DeviceDesc` 含 `Keyboard` 的集合；
4. 用 `-Match` 子串过滤（默认 `VID_256C&PID_0064`、`bigmax_hid_drv`）；
5. 读取当前 `ConfigFlags`，与目标值比较；
6. 写 `ConfigFlags`，调用 `pnputil /restart-device`；
7. 再读一次 `ConfigFlags` 验证；
8. 全过程写入 `logs\fix-YYYYMMDD-HHmmss.log`。

`-Undo` 只是把目标值改成 `0`。

## 6. 局限

- 8 个功能键、锁屏、截图和 B/E 在同一个键盘集合上，停用后一起失效。
- 驱动更新、换 USB 口、Windows 大版本更新可能重新枚举设备并把 `ConfigFlags` 重置；重新运行脚本即可。
- 某些机型可能没有独立的 `kbdhid` 集合，或者 B/E 来自厂商自定义集合；那种情况脚本找不到目标，需要按 [compatibility.md](compatibility.md) 调整。
- 这不是内核过滤驱动；它不拦截任何输入，只是让 Windows 不启动那个 HID 集合，因此没有常驻进程、没有兼容性风险。

## 7. 考虑过但没采用的方案

| 方案 | 结论 |
|---|---|
| `WH_KEYBOARD_LL` 过滤 B/E | 驱动用 PostMessage 注入，钩子收不到 |
| Raw Input + 拦截 | Raw Input 是副本，不能阻止注入 |
| `pnputil /disable-device` | 键盘类设备被判定为 critical，拒绝 |
| 官方驱动里改按键映射 | 只在驱动运行时生效；不开驱动仍会从固件/键盘集合发出 |
| 内核过滤驱动 | 可行，但需要签名/安装驱动，成本和风险都高 |
| 修改 Windows “每次滚动行数” | 能加快圆盘，但会影响普通鼠标滚轮，且不是按设备生效 |

设备层禁用键盘集合是成本最低、可逆、无需常驻进程的方案。
