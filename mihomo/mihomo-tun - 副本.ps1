# Mihomo TUN 管理脚本

# 管理员提权
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process pwsh.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Set-Location $PSScriptRoot

# 配置
$workDir = "$env:USERPROFILE\.config\mihomo"
$configFile = Join-Path $workDir "config.yaml"
$configUrl = "****"   # 替换为你的订阅地址

# 获取可执行文件路径与进程名
$exePath = (Get-Command mihomo* -ErrorAction SilentlyContinue).Source
if (-not $exePath) { $exePath = (Get-ChildItem $workDir -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
$procName = if ($exePath) { [IO.Path]::GetFileNameWithoutExtension($exePath) } else { $null }

# 检查 TUN 配置
function Test-Tun { (Get-Content $configFile -Raw) -match '(?m)^tun:' }

# 启动
function Start-Tun {
    if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
        Write-Host "Mihomo 已在运行"
        return
    }
    if (-not $exePath) { Write-Host "找不到 mihomo 可执行文件"; return }
    if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir -Force | Out-Null }
    curl.exe -L $configUrl -o $configFile -s
    if (-not (Test-Path $configFile)) { Write-Host "配置下载失败"; return }
    if (-not (Test-Tun)) { Write-Host "配置文件中无 tun: 字段，无法启动"; return }

    Start-Process -FilePath $exePath -ArgumentList "-d `"$workDir`" -f `"$configFile`"" -WindowStyle Hidden
    Start-Sleep -Seconds 2
    if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
        Write-Host "Mihomo (TUN) 已启动"
    } else {
        Write-Host "启动失败"
    }
}

# 停止
function Stop-Tun {
    $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($proc) {
        $proc | Stop-Process -Force
        Write-Host "Mihomo 已停止"
    } else {
        Write-Host "Mihomo 未运行"
    }
}

# 主菜单（仅执行一次）
Clear-Host
$running = Get-Process -Name $procName -ErrorAction SilentlyContinue
Write-Host "--- Mihomo TUN 管理 ---"
Write-Host "状态: $(if ($running) { '运行中' } else { '未运行' })"
Write-Host "1. 启动"
Write-Host "2. 停止"
$choice = Read-Host "请选择"
switch ($choice) {
    "1" { Start-Tun }
    "2" { Stop-Tun }
    default { Write-Host "无效选项" }
}

# 显示状态并等待3秒后退出
Write-Host "当前状态: $(if (Get-Process -Name $procName -ErrorAction SilentlyContinue) { '运行中' } else { '未运行' })"
Start-Sleep -Seconds 3
exit