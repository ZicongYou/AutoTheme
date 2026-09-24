# AutoTheme

**Windows 10/11 日出日落自动切换深色 / 浅色主题。** 天黑变深色，天亮变浅色。

- 🪶 **轻**：不常驻后台，不占内存。系统计划任务每 5 分钟看一眼，大部分时候 0.3 秒就结束。
- 🧱 **稳**：没有后台进程可崩；登录、解锁、睡眠唤醒都会立即检查一次。
- 📍 **自动定位**：用 Windows 自带定位服务获取位置，出差/旅行换了城市自动跟着变；定位不可用时按系统时区估算。
- 🔌 **离线**：日出日落在本地计算（NOAA 算法），不联网、不上传任何数据。
- 📖 **开源透明**：纯 PowerShell 脚本，200 行左右，能直接读懂它做了什么。
- 🔑 不需要管理员权限。

[English](#english)

## 安装

1. 到 [Releases](../../releases/latest) 下载 `AutoTheme.zip` 并解压。
2. 双击 `install.cmd`。
   - 如果弹出“安全警告 / Windows 已保护你的电脑”，点“运行”或“更多信息 → 仍要运行”（因为文件是从网上下载的）。
3. 完成。主题会立刻按当前时间切换一次。

程序安装在 `%LOCALAPPDATA%\AutoTheme`，解压出来的文件夹之后可以删掉。

### 定位更准

打开 **设置 → 隐私和安全性 → 位置**，开启“位置服务”和“允许桌面应用访问你的位置”。
不开也能用，会按系统时区取一个代表城市，误差一般在几十分钟以内。

换了地方时，建议同时开启 **设置 → 时间和语言 → 日期和时间 → 自动设置时区**，时区一变程序会立刻重新定位。

## 卸载

双击 `%LOCALAPPDATA%\AutoTheme\uninstall.cmd`（把这个路径粘进资源管理器地址栏即可打开）。卸载不会改动你当前的主题。

## 自定义

用记事本打开 `%LOCALAPPDATA%\AutoTheme\autotheme.ps1`，改开头的配置：

| 配置 | 说明 |
|---|---|
| `$SunriseOffsetMin` | 日出后多少分钟切浅色，可以为负（提前） |
| `$SunsetOffsetMin` | 日落后多少分钟切深色，可以为负（提前） |
| `$LocationRefreshMin` | 多久重新定位一次，默认 60 分钟 |

临时手动切换（最多 5 分钟后会按时间自动切回）：

```
powershell -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\AutoTheme\autotheme.ps1" -Force dark
```

## 排查问题

- 日志：`%LOCALAPPDATA%\AutoTheme\autotheme.log`，每次切换、位置变化、出错都会记录。
- 计划任务：打开“任务计划程序”，找到 `AutoTheme`。

## 工作原理

1. 获取位置：Windows 定位服务 → 同一时区下上次成功的定位 → 按时区估算。
2. 按经纬度算出今天的日出日落时间。
3. 修改 `HKCU\...\Themes\Personalize` 下的 `AppsUseLightTheme` 和 `SystemUsesLightTheme`，再广播设置变更，任务栏和应用即时刷新。

极昼 / 极夜地区算不出日出日落时，按 7:00–19:00 为白天处理。

---

## English

**Automatically switch Windows 10/11 between dark and light mode at sunset and sunrise.**

- Lightweight: no background process. A scheduled task checks every 5 minutes (and on logon / unlock / wake), usually finishing in 0.3 s.
- Uses Windows Location to follow you when you travel; falls back to your time zone if location is unavailable.
- Sunrise/sunset are computed locally — no network access, no data leaves your PC.
- Plain PowerShell (~200 lines), no admin rights required.

**Install:** download `AutoTheme.zip` from [Releases](../../releases/latest), extract, double-click `install.cmd`.
**Uninstall:** run `%LOCALAPPDATA%\AutoTheme\uninstall.cmd`.
**Configure:** edit the variables at the top of `%LOCALAPPDATA%\AutoTheme\autotheme.ps1` (offsets in minutes, location refresh interval).
**Logs:** `%LOCALAPPDATA%\AutoTheme\autotheme.log`.

For better accuracy, enable *Settings → Privacy & security → Location* and *Let desktop apps access your location*.

## License

[MIT](LICENSE)
