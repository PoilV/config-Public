# Mihomo 代理切换工具
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==================== 配置区域 ====================
# 请根据需要修改以下路径配置
$workDir = "$env:USERPROFILE\.config\mihomo"  # Mihomo 工作目录
$configFileName = "config.yaml"  # 配置文件名
$configUrl = "***"  # 配置文件下载地址
# ================================================

# 初始化变量
$configPath = Join-Path $workDir $configFileName
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

# --- 核心函数 ---

function Get-MihomoExePath {
    # 从PATH中查找应用，如果找不到就从工作目录中查找
    $exePath = & where.exe *.exe 2>$null | Where-Object { $_ -like "*mihomo*" } | Select-Object -First 1
    if (-not $exePath) {
        $exePath = (Get-ChildItem $workDir -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }
    return $exePath
}

function Get-MihomoProcess {
    $exePath = Get-MihomoExePath
    if ($exePath) {
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
        return Get-Process -Name $processName -ErrorAction SilentlyContinue
    }
    return $null
}

function Test-MihomoRunning {
    $process = Get-MihomoProcess
    return $null -ne $process
}

function Start-MihomoService {
    $exePath = Get-MihomoExePath

    if (!(Test-Path $exePath)) {
        Write-Host "错误: 找不到 Mihomo 可执行文件" -ForegroundColor Red
        return $false
    }

    # 确保目录存在
    if (!(Test-Path $workDir)) {
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    }

    # 下载配置文件（如果不存在）
    if (!(Test-Path $configPath)) {
        Write-Host "-> 下载配置文件..." -ForegroundColor Cyan
        curl.exe -L $configUrl -o $configPath -s
    }

    # 启动服务
    Write-Host "-> 启动 Mihomo 服务..." -ForegroundColor Cyan
    Start-Process -FilePath $exePath -ArgumentList "-d `"$workDir`" -f `"$configPath`"" -WorkingDirectory $workDir -WindowStyle Hidden
    Start-Sleep -Seconds 2

    # 验证启动
    if (Test-MihomoRunning) {
        Write-Host "✓ Mihomo 服务启动成功" -ForegroundColor Green
        return $true
    } else {
        Write-Host "⚠ Mihomo 服务启动可能失败" -ForegroundColor Yellow
        return $false
    }
}

function Stop-MihomoService {
    $process = Get-MihomoProcess
    if ($process) {
        try {
            Stop-Process -Id $process.Id -Force
            Write-Host "✓ Mihomo 服务已停止" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "错误: 停止服务失败" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "⚠ Mihomo 服务未在运行" -ForegroundColor Yellow
        return $true
    }
}

function Update-System {
    # 强制刷新系统代理设置
    $signature = '[DllImport("wininet.dll", SetLastError = true)] public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);'
    $type = Add-Type -MemberDefinition $signature -Name "WinInet" -Namespace "WinInetInterop" -PassThru
    $type::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    $type::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Set-ProxyEnabled {
    param([bool]$Enable)
    try {
        if ($Enable) {
            Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1 -ErrorAction Stop
            Set-ItemProperty -Path $regPath -Name AutoDetect -Value 1 -ErrorAction Stop
        } else {
            Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0 -ErrorAction Stop
        }
        Update-System
        return $true
    } catch {
        Write-Host "错误: 代理设置失败" -ForegroundColor Red
        return $false
    }
}

function Get-ProxyStatus {
    try {
        $proxyEnable = (Get-ItemProperty -Path $regPath -ErrorAction Stop).ProxyEnable
        return $proxyEnable -eq 1
    } catch {
        return $false
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Gray
    Write-Host "         Mihomo 代理切换工具" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Gray

    # 显示状态
    $mihomoRunning = Test-MihomoRunning
    if ($mihomoRunning) {
        $process = Get-MihomoProcess
        Write-Host "[ Mihomo 状态: 运行中 (PID: $($process.Id)) ]" -ForegroundColor Green
    } else {
        Write-Host "[ Mihomo 状态: 未运行 ]" -ForegroundColor Yellow
    }

    $proxyEnabled = Get-ProxyStatus
    if ($proxyEnabled) {
        Write-Host "[ 系统代理状态: 已开启 ]" -ForegroundColor Green
    } else {
        Write-Host "[ 系统代理状态: 已关闭 ]" -ForegroundColor Yellow
    }

    Write-Host "----------------------------------------"
    Write-Host " 1. 开启系统代理"
    Write-Host " 2. 关闭系统代理"
    Write-Host " 3. 刷新状态"
    Write-Host " 4. 停止 Mihomo"
    Write-Host " 5. 退出"
    Write-Host "----------------------------------------"
}

# --- 主程序 ---

Write-Host "正在检查 Mihomo 运行状态..." -ForegroundColor Gray

if (!(Test-MihomoRunning)) {
    Write-Host "[!] 检测到 Mihomo 未运行，准备启动..." -ForegroundColor Yellow
    if (!(Start-MihomoService)) {
        Write-Host "按回车键进入菜单管理代理..." -ForegroundColor Yellow
        Read-Host
    }
} else {
    $process = Get-MihomoProcess
    Write-Host "[√] Mihomo 已在运行中 (PID: $($process.Id))" -ForegroundColor Green
    Start-Sleep -Seconds 1
}

# --- 代理管理菜单 ---

while ($true) {
    Show-Menu
    $choice = Read-Host "请输入选项 (1-5)"

    switch ($choice) {
        "1" {
            Write-Host "正在开启系统代理..." -ForegroundColor Cyan
            if (Set-ProxyEnabled -Enable $true) {
                Write-Host "✓ 系统代理已启用" -ForegroundColor Green
            }
            Start-Sleep -Seconds 1
        }
        "2" {
            Write-Host "正在关闭系统代理..." -ForegroundColor Cyan
            if (Set-ProxyEnabled -Enable $false) {
                Write-Host "✓ 系统代理已关闭" -ForegroundColor Green
            }
            Start-Sleep -Seconds 1
        }
        "3" {
            Write-Host "正在刷新状态..." -ForegroundColor Cyan
            Update-System
            Write-Host "✓ 状态已刷新" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
        "4" {
            Write-Host "正在停止 Mihomo 并关闭代理..." -ForegroundColor Cyan
            Stop-MihomoService
            Set-ProxyEnabled -Enable $false
            Write-Host "✓ 系统代理已关闭" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
        "5" {
            Write-Host "再见！" -ForegroundColor Cyan
            exit
        }
        default {
            Write-Host "无效输入，请输入 1-5 之间的数字" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
