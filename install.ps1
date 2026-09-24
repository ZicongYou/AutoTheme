# AutoTheme 安装：复制到 %LOCALAPPDATA%\AutoTheme 并注册计划任务（仅当前用户，不需要管理员）

$ErrorActionPreference = 'Stop'
$src  = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'AutoTheme'
$task = 'AutoTheme'

Write-Host '正在安装 AutoTheme ...'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $src 'autotheme.ps1') $dest -Force
Copy-Item (Join-Path $src 'uninstall.ps1') $dest -Force
Copy-Item (Join-Path $src 'uninstall.cmd') $dest -Force
# 去掉从网上下载带来的“来自其他计算机”标记
Get-ChildItem $dest -File | Unblock-File

$user   = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$script = Join-Path $dest 'autotheme.ps1'
# conhost --headless 让 PowerShell 完全不弹窗
$args_  = "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`""
$args_  = [Security.SecurityElement]::Escape($args_)
$userX  = [Security.SecurityElement]::Escape($user)
$start  = (Get-Date).ToString('yyyy-MM-ddT00:00:00')

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>AutoTheme: 按日出日落自动切换 Windows 深浅色主题</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$userX</UserId></LogonTrigger>
    <SessionStateChangeTrigger><Enabled>true</Enabled><StateChange>SessionUnlock</StateChange><UserId>$userX</UserId></SessionStateChangeTrigger>
    <EventTrigger><Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription></EventTrigger>
    <TimeTrigger><Enabled>true</Enabled><StartBoundary>$start</StartBoundary><Repetition><Interval>PT5M</Interval></Repetition></TimeTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$userX</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT2M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author"><Exec><Command>conhost.exe</Command><Arguments>$args_</Arguments></Exec></Actions>
</Task>
"@
Register-ScheduledTask -TaskName $task -Xml $xml -Force | Out-Null

# 定位权限提示（没开也能用，会按时区估算位置）
$loc = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
$ok = (Get-ItemProperty $loc -ErrorAction SilentlyContinue).Value -eq 'Allow' -and
      (Get-ItemProperty "$loc\NonPackaged" -ErrorAction SilentlyContinue).Value -ne 'Deny'
if (-not $ok) {
    Write-Host ''
    Write-Host '提示：定位服务未开启，将按系统时区估算位置（误差可能有几十分钟）。' -ForegroundColor Yellow
    Write-Host '想更准：设置 → 隐私和安全性 → 位置 → 打开“位置服务”和“允许桌面应用访问你的位置”。' -ForegroundColor Yellow
}

Start-ScheduledTask -TaskName $task
Write-Host ''
Write-Host "安装完成。程序位于 $dest，日志见 autotheme.log。" -ForegroundColor Green
Write-Host '卸载：运行该目录下的 uninstall.cmd'
