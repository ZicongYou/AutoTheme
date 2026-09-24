# AutoTheme 卸载：删除计划任务和程序目录（不改动当前主题）

$dest = Join-Path $env:LOCALAPPDATA 'AutoTheme'
Unregister-ScheduledTask -TaskName 'AutoTheme' -Confirm:$false -ErrorAction SilentlyContinue
# 本脚本可能就在 $dest 里运行，交给一个独立进程等我们退出后再删目录
Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $env:TEMP -ArgumentList @(
    '-NoProfile', '-Command', "Start-Sleep 3; Remove-Item -LiteralPath '$dest' -Recurse -Force")
Write-Host 'AutoTheme 已卸载。' -ForegroundColor Green
Start-Sleep 2
