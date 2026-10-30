# 日出日落自动切换 Windows 深浅色主题
# 由计划任务定时调用（每 5 分钟 + 登录 + 解锁 + 睡眠唤醒），每次只做一次判断，不常驻进程。
# 手动强制：autotheme.ps1 -Force dark / light

param([ValidateSet('dark', 'light')][string]$Force)

# ---- 配置 ----
$SunriseOffsetMin = 0   # 日出后多少分钟切浅色（可为负）
$SunsetOffsetMin  = 0   # 日落后多少分钟切深色（可为负）
$LocationRefreshMin = 60  # 多久重新定位一次
# 位置来源优先级：Windows 定位服务 → 上次成功定位的缓存 → 按系统时区估算
# --------------

$ErrorActionPreference = 'Stop'
$LogFile  = Join-Path $PSScriptRoot 'autotheme.log'
$LocFile  = Join-Path $PSScriptRoot 'location.json'
$StateFile = Join-Path $PSScriptRoot 'state.json'

function Write-Log($msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    # 日志超过 200KB 截掉旧的一半
    if ((Get-Item $LogFile).Length -gt 200KB) {
        $all = Get-Content $LogFile -Encoding UTF8
        $all[([int]($all.Count / 2))..($all.Count - 1)] | Set-Content $LogFile -Encoding UTF8
    }
}

# 时区 → 代表城市坐标，定位完全不可用时兜底
$TzCoords = @{
    'AUS Eastern Standard Time'  = -33.87, 151.21   # 悉尼/墨尔本/堪培拉
    'E. Australia Standard Time' = -27.47, 153.03   # 布里斯班
    'Cen. Australia Standard Time' = -34.93, 138.60 # 阿德莱德
    'AUS Central Standard Time'  = -12.46, 130.84   # 达尔文
    'W. Australia Standard Time' = -31.95, 115.86   # 珀斯
    'Tasmania Standard Time'     = -42.88, 147.33   # 霍巴特
    'New Zealand Standard Time'  = -36.85, 174.76   # 奥克兰
    'China Standard Time'        = 31.23, 121.47    # 上海（北京 39.9,116.4 差不了几分钟）
    'Taipei Standard Time'       = 25.03, 121.57
    'Tokyo Standard Time'        = 35.68, 139.69
    'Korea Standard Time'        = 37.57, 126.98
    'Singapore Standard Time'    = 1.35, 103.82
    'SE Asia Standard Time'      = 13.75, 100.50    # 曼谷
    'India Standard Time'        = 28.61, 77.21
    'GMT Standard Time'          = 51.51, -0.13     # 伦敦
    'W. Europe Standard Time'    = 52.52, 13.40     # 柏林
    'Romance Standard Time'      = 48.86, 2.35      # 巴黎
    'Eastern Standard Time'      = 40.71, -74.01    # 纽约
    'Central Standard Time'      = 41.88, -87.63    # 芝加哥
    'Mountain Standard Time'     = 39.74, -104.99   # 丹佛
    'Pacific Standard Time'      = 34.05, -118.24   # 洛杉矶
}

function Get-WindowsLocation {
    try {
        Add-Type -AssemblyName System.Device
        $w = New-Object System.Device.Location.GeoCoordinateWatcher
        $w.Start()
        for ($i = 0; $i -lt 30 -and $w.Position.Location.IsUnknown; $i++) {
            if ($w.Permission -eq 'Denied' -or $w.Status -eq 'Disabled') { break }
            Start-Sleep -Milliseconds 500
        }
        $c = $w.Position.Location
        $w.Stop()
        if (-not $c.IsUnknown) { return @{ Lat = $c.Latitude; Lon = $c.Longitude } }
    } catch {}
    return $null
}

# 缓存 location.json 字段：
#   Lat/Lon/OkTz  最近一次成功定位的坐标及当时时区
#   TriedAt       最近一次尝试定位的时间（无论成败），用来控制重试频率
function Get-MyLocation {
    $tz = (Get-TimeZone).Id
    $c = $null
    if (Test-Path $LocFile) { try { $c = Get-Content $LocFile -Raw | ConvertFrom-Json } catch {} }
    $hasOk = $c -and $null -ne $c.Lat -and $c.OkTz -eq $tz   # 旧坐标可信：时区没变
    $recent = $c -and $c.TriedAt -and ((Get-Date) - [datetime]$c.TriedAt).TotalMinutes -lt $LocationRefreshMin

    # 时区变了说明大概率换了地方，立刻重新定位；否则按间隔重试
    if (-not $recent -or -not $hasOk) {
        $loc = if ($recent -and $c.TriedTz -eq $tz) { $null } else { Get-WindowsLocation }
        if ($loc) {
            $moved = -not $c -or $null -eq $c.Lat -or [math]::Abs($c.Lat - $loc.Lat) -gt 0.5 -or [math]::Abs($c.Lon - $loc.Lon) -gt 0.5
            @{ Lat = $loc.Lat; Lon = $loc.Lon; OkTz = $tz; TriedAt = (Get-Date).ToString('o'); TriedTz = $tz } | ConvertTo-Json | Set-Content $LocFile
            if ($moved) { Write-Log ("位置更新为 {0:N2}, {1:N2}" -f $loc.Lat, $loc.Lon) }
            return @{ Lat = $loc.Lat; Lon = $loc.Lon; Src = '定位' }
        }
        if (-not ($recent -and $c.TriedTz -eq $tz)) {
            @{ Lat = $c.Lat; Lon = $c.Lon; OkTz = $c.OkTz; TriedAt = (Get-Date).ToString('o'); TriedTz = $tz } | ConvertTo-Json | Set-Content $LocFile
        }
    }
    if ($hasOk) { return @{ Lat = $c.Lat; Lon = $c.Lon; Src = '定位缓存' } }
    if ($TzCoords.ContainsKey($tz)) {
        $xy = $TzCoords[$tz]
        return @{ Lat = $xy[0]; Lon = $xy[1]; Src = "时区 $tz" }
    }
    # 未收录的时区：经度按 UTC 偏移估，纬度默认北纬 30
    return @{ Lat = 30; Lon = (Get-TimeZone).BaseUtcOffset.TotalHours * 15; Src = "时区偏移估算 $tz" }
}

# NOAA / Almanac for Computers 日出日落算法，返回本地时间；极昼极夜返回 $null
function Get-SunEvent([datetime]$Date, [bool]$Rise) {
    $rad = [math]::PI / 180
    $zenith = 90.833
    $N = $Date.DayOfYear
    $lngHour = $Longitude / 15
    $t = $N + ((($(if ($Rise) { 6 } else { 18 })) - $lngHour) / 24)
    $M = 0.9856 * $t - 3.289
    $L = $M + 1.916 * [math]::Sin($M * $rad) + 0.020 * [math]::Sin(2 * $M * $rad) + 282.634
    $L = (($L % 360) + 360) % 360
    $RA = [math]::Atan(0.91764 * [math]::Tan($L * $rad)) / $rad
    $RA = (($RA % 360) + 360) % 360
    $RA = ($RA + ([math]::Floor($L / 90) * 90 - [math]::Floor($RA / 90) * 90)) / 15
    $sinDec = 0.39782 * [math]::Sin($L * $rad)
    $cosDec = [math]::Cos([math]::Asin($sinDec))
    $cosH = ([math]::Cos($zenith * $rad) - $sinDec * [math]::Sin($Latitude * $rad)) / ($cosDec * [math]::Cos($Latitude * $rad))
    if ($cosH -gt 1 -or $cosH -lt -1) { return $null }
    $H = [math]::Acos($cosH) / $rad
    if ($Rise) { $H = 360 - $H }
    $H = $H / 15
    $T = $H + $RA - 0.06571 * $t - 6.622
    $UT = ((($T - $lngHour) % 24) + 24) % 24

    # UT 可能落在 UTC 的前一天/后一天，调整到本地日期一致
    $utcMidnight = [datetime]::SpecifyKind($Date.Date, [DateTimeKind]::Utc)
    $local = $utcMidnight.AddHours($UT).ToLocalTime()
    while ($local.Date -gt $Date.Date) { $local = $local.AddDays(-1) }
    while ($local.Date -lt $Date.Date) { $local = $local.AddDays(1) }
    return $local
}

# 广播设置变化，让任务栏/开始菜单/资源管理器/应用重新读取颜色。内容没变时重发不会有可见变化
function Send-ThemeRefresh {
    if (-not ('AutoTheme.Native' -as [type])) {
        Add-Type -Namespace AutoTheme -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $r = [UIntPtr]::Zero
    foreach ($p in 'ImmersiveColorSet', 'WindowsThemeElement') {
        [void][AutoTheme.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, $p, 2, 3000, [ref]$r)
    }
}

# 任务栏只认注册表值的变化，不认广播：锁屏时错过了变化就会一直停在旧颜色。
# 把 SystemUsesLightTheme 来回改一次，人为制造变化逼它重画（任务栏会闪一下）
function Repair-Taskbar {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $want = [int](Get-ItemProperty $key).SystemUsesLightTheme
    try {
        Set-ItemProperty $key -Name SystemUsesLightTheme -Value (1 - $want) -Type DWord
        Send-ThemeRefresh
        Start-Sleep -Milliseconds 1500
    } finally {
        Set-ItemProperty $key -Name SystemUsesLightTheme -Value $want -Type DWord
        Send-ThemeRefresh
    }
}

# 锁屏界面在当前会话里运行 = 屏幕锁着，此时桌面组件常常收不到刷新通知
function Test-Locked {
    $sid = (Get-Process -Id $PID).SessionId
    [bool](Get-Process LogonUI -ErrorAction SilentlyContinue | Where-Object SessionId -eq $sid)
}

# 只写注册表，返回是否真的改了
function Set-Theme([bool]$Light) {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $want = [int]$Light
    $cur = Get-ItemProperty $key -ErrorAction SilentlyContinue
    if ($cur.AppsUseLightTheme -eq $want -and $cur.SystemUsesLightTheme -eq $want) { return $false }
    Set-ItemProperty $key -Name AppsUseLightTheme    -Value $want -Type DWord
    Set-ItemProperty $key -Name SystemUsesLightTheme -Value $want -Type DWord
    return $true
}

# state.json：RefreshUntil 切换后补发刷新的截止时间；Pending 切换时屏幕锁着，解锁后要补发
function Get-State {
    $s = $null
    if (Test-Path $StateFile) { try { $s = Get-Content $StateFile -Raw | ConvertFrom-Json } catch {} }
    if (-not $s) { $s = [pscustomobject]@{ RefreshUntil = $null; Pending = $false } }
    return $s
}
function Save-State($s) { $s | ConvertTo-Json | Set-Content $StateFile }

try {
    $now = Get-Date
    if ($Force) {
        $light = $Force -eq 'light'
        $why = "手动强制"
    } else {
        $loc = Get-MyLocation
        $Latitude = $loc.Lat; $Longitude = $loc.Lon
        $rise = Get-SunEvent $now $true
        $set  = Get-SunEvent $now $false
        if (-not $rise -or -not $set) {
            # 极昼/极夜兜底：7:00-19:00 浅色
            $rise = $now.Date.AddHours(7); $set = $now.Date.AddHours(19)
        }
        $rise = $rise.AddMinutes($SunriseOffsetMin)
        $set  = $set.AddMinutes($SunsetOffsetMin)
        $light = ($now -ge $rise) -and ($now -lt $set)
        $why = "日出 {0:HH:mm} 日落 {1:HH:mm}，位置来源：{2}" -f $rise, $set, $loc.Src
    }

    $state = Get-State
    $locked = Test-Locked
    if (Set-Theme $light) {
        Write-Log ("切换到{0}（{1}）{2}" -f $(if ($light) { '浅色' } else { '深色' }), $why, $(if ($locked) { '，锁屏中，解锁后补刷新' } else { '' }))
        Send-ThemeRefresh
        $state.RefreshUntil = $now.AddMinutes(15).ToString('o')
        $state.Pending = $locked
        Save-State $state
        # 刚切换时部分组件还在重绘，几秒后再发一次
        if (-not $locked) { Start-Sleep 4; Send-ThemeRefresh }
    } elseif ($state.Pending) {
        # 解锁触发时锁屏界面可能还没退，最多等 15 秒
        for ($i = 0; $i -lt 15 -and $locked; $i++) { Start-Sleep 1; $locked = Test-Locked }
        if (-not $locked) {
            Start-Sleep 5
            Repair-Taskbar
            $state.Pending = $false
            $state.RefreshUntil = (Get-Date).AddMinutes(15).ToString('o')
            Save-State $state
            Write-Log "解锁后重画任务栏"
        }
    } elseif ($state.RefreshUntil -and $now -lt [datetime]$state.RefreshUntil -and -not $locked) {
        Send-ThemeRefresh
    }
} catch {
    Write-Log "出错: $_"
    exit 1
}
