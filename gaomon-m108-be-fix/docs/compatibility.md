# 兼容性与自定义匹配

## 已验证

| 设备 | 内部型号 | USB ID | 系统 | 驱动 | 结果 |
|---|---|---|---|---|---|
| GAOMON M108 | `GM001_T208` | `VID_256C / PID_0064` | Windows 11 | 16.0.0.218 | B/E 消失；笔/压感/鼠标/音量正常 |

## 可能适用

任何满足以下条件的 GAOMON / HUION 数位板：

- 在设备管理器里，数位板下面有一个 **HID Keyboard Device**（`Service = kbdhid`）；
- 不启动官方驱动时，笔侧键/功能键会向焦点窗口输入字符。

脚本只按 `kbdhid` / `Keyboard` 过滤，不会碰笔、鼠标、Consumer Control，因此对同结构的机型是安全的。

## 默认匹配

```text
VID_256C&PID_0064      # M108；同 VID/PID 的 HUION/GAOMON 设备
bigmax_hid_drv         # GAOMON 内核驱动创建的虚拟键盘
```

## 找到自己设备的 VID/PID

1. 打开 **设备管理器**（`devmgmt.msc`）；
2. 展开 **键盘** 或 **人体学输入设备**；
3. 找到数位板对应的 **HID Keyboard Device**（可以拔插数位板看哪个消失/出现）；
4. 右键 → **属性** → **详细信息** → 选择 **设备实例路径**；
5. 记录形如：

```
HID\VID_256C&PID_0064&MI_02&Col04\b&1b51d34f&0&0003
```

其中 `VID_256C&PID_0064` 就是匹配串。

也可以直接运行只读脚本查看当前机器上匹配到的集合：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-TabletKeyboardState.ps1
```

换一个匹配串：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-TabletKeyboardState.ps1 -Match "VID_1234&PID_5678"
```

## 自定义禁用

```powershell
.\scripts\Disable-TabletKeyboard.ps1 -Match "VID_1234&PID_5678","bigmax_hid_drv"
```

恢复：

```powershell
.\scripts\Disable-TabletKeyboard.ps1 -Undo -Match "VID_1234&PID_5678","bigmax_hid_drv"
```

> 自定义 `-Match` 时，脚本的自提升不会自动把参数传给子进程（避免转义问题）。建议在**已提升的 PowerShell** 里运行，或直接编辑脚本顶部的默认 `$Match`。

## 找不到目标

如果 `Get-TabletKeyboardState.ps1` 输出 `No matching keyboard HID collections found`：

1. 确认数位板已连接、驱动已安装；
2. 确认设备管理器里确实有 `HID Keyboard Device`；
3. 用 `-Match` 换成该设备的 VID/PID；
4. 如果只有厂商自定义集合（`FF00`/`FF01`）而没有 `kbdhid`，本脚本不适用——B/E 可能来自厂商集合，需要单独分析报告。

## 失效与恢复

- 停用键盘集合后，8 个功能键、锁屏、截图等**同一接口**上的键会失效；
- 笔尖、压感、悬停、左右键、笔在板面上滑动滚页面、音量键不受影响；
- 运行 `enable-tablet-keyboard.cmd` 可恢复；
- 重装/升级驱动或换 USB 口后，重新运行 `disable-tablet-keyboard.cmd`。
