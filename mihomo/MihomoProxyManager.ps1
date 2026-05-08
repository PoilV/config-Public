# Mihomo 代理管理工具 - 用于启动/停止代理服务和切换系统代理

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==================== 配置区域 ====================
$workDir = "$env:USERPROFILE\.config\mihomo"              # 工作目录
$configPath = Join-Path $workDir "config.yaml"            # 配置文件路径
$configUrl = "***"  # 配置下载地址
$proxyServer = "127.0.0.1:7890"                           # 代理服务器地址
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"  # 系统代理注册表路径
# ==================================================

# 全局变量
$WinInetType = $null

# 获取 Mihomo 可执行文件路径（优先从 PATH 查找，否则在工作目录查找）
function Get-MihomoExePath {
    $exe = Get-Command mihomo* -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { return $exe.Source }
    
    $exe = Get-ChildItem $workDir -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { return $exe.FullName }
    
    return $null
}

# 获取当前运行的 Mihomo 进程
function Get-MihomoProcess {
    $exePath = Get-MihomoExePath
    if ($exePath) {
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
        return Get-Process -Name $processName -ErrorAction SilentlyContinue
    }
    return $null
}

# 启动 Mihomo 服务（检查运行状态 -> 创建工作目录 -> 下载配置 -> 启动进程）
function Start-Mihomo {
    $proc = Get-MihomoProcess
    if ($proc) {
        Write-Host "Mihomo 已在运行 (PID: $($proc.Id))" -ForegroundColor Yellow
        return $true
    }

    $exePath = Get-MihomoExePath
    if (-not $exePath) {
        Write-Host "错误: 找不到 Mihomo 可执行文件" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $workDir)) {
        Write-Host "创建工作目录: $workDir" -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    }

    Write-Host "正在下载配置文件..." -ForegroundColor Cyan
    curl.exe -L $configUrl -o $configPath -s
    if (Test-Path $configPath) {
        Write-Host "配置文件下载成功" -ForegroundColor Green
    } else {
        Write-Host "配置文件下载失败" -ForegroundColor Red
        return $false
    }

    Write-Host "启动 Mihomo..." -ForegroundColor Cyan
    try {
        $arguments = "-d `"$workDir`" -f `"$configPath`""
        Start-Process -FilePath $exePath -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory $workDir

        $timeout = 5
        $elapsed = 0
        while ($elapsed -lt $timeout) {
            Start-Sleep -Milliseconds 500
            $elapsed += 0.5
            $proc = Get-MihomoProcess
            if ($proc) {
                Write-Host "Mihomo 已启动 (PID: $($proc.Id))" -ForegroundColor Green
                return $true
            }
        }
        Write-Host "启动超时，请检查配置文件或路径" -ForegroundColor Red
        return $false
    } catch {
        Write-Host "启动失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 停止 Mihomo 服务
function Stop-Mihomo {
    $proc = Get-MihomoProcess
    if ($proc) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-Host "Mihomo 已停止" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "停止失败: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    Write-Host "Mihomo 未运行" -ForegroundColor Yellow
    return $true
}

# 初始化 WinInet API（用于刷新系统代理）
function Initialize-WinInet {
    if (-not $WinInetType) {
        try {
            $signature = @'
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
'@
            $typeName = "WinInet$(Get-Random)"
            $script:WinInetType = Add-Type -MemberDefinition $signature -Name $typeName -Namespace WinInetInterop -PassThru
        } catch {
            Write-Host "警告: 初始化 WinInet 类型失败: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# 刷新系统代理设置（使注册表修改立即生效）
function Update-System {
    Initialize-WinInet
    if ($WinInetType) {
        try {
            $WinInetType::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
            $WinInetType::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
            return $true
        } catch {
            Write-Host "警告: 刷新代理设置失败: $($_.Exception.Message)" -ForegroundColor Yellow
            return $false
        }
    }
    return $false
}

# 设置系统代理状态（修改注册表并刷新）
function Set-Proxy {
    param([bool]$Enable)

    $registrySuccess = $true
    
    try {
        Set-ItemProperty -Path $regPath -Name ProxyEnable -Value ([int]$Enable) -ErrorAction Stop
        if ($Enable) {
            Set-ItemProperty -Path $regPath -Name ProxyServer -Value $proxyServer -ErrorAction Stop
        }
    } catch {
        Write-Host "警告: 注册表设置失败: $($_.Exception.Message)" -ForegroundColor Yellow
        $registrySuccess = $false
    }

    $refreshSuccess = Update-System
    return $refreshSuccess -or $registrySuccess
}

# 显示主菜单
function Show-Menu {
    Clear-Host
    $proc = Get-MihomoProcess
    $proxyOn = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).ProxyEnable -eq 1

    Write-Host "========== Mihomo 代理管理工具 ==========" -ForegroundColor Cyan
    $serviceStatus = if ($proc) { "运行中 (PID: $($proc.Id))" } else { "未运行" }
    $serviceColor = if ($proc) { "Green" } else { "Red" }
    Write-Host "Mihomo 服务: $serviceStatus" -ForegroundColor $serviceColor
    $proxyStatus = if ($proxyOn) { "已开启" } else { "已关闭" }
    $proxyColor = if ($proxyOn) { "Green" } else { "Yellow" }
    Write-Host "系统代理: $proxyStatus" -ForegroundColor $proxyColor
    Write-Host "代理服务器: $proxyServer" -ForegroundColor Gray
    Write-Host "------------------------------------------"
    Write-Host "PowerShell 代理命令：" -ForegroundColor Cyan
    Write-Host "`$env:HTTP_PROXY='http://$proxyServer'; `$env:HTTPS_PROXY='http://$proxyServer'" -ForegroundColor Gray
    Write-Host "------------------------------------------"
    Write-Host " [1] 启动 Mihomo 并开启代理"
    Write-Host " [2] 停止 Mihomo 并关闭代理"
    Write-Host " [3] 切换系统代理状态"
    Write-Host " [4] 退出"
    Write-Host "------------------------------------------"
    Write-Host "提示: 按 1-4 选择，或按 Ctrl+C 退出" -ForegroundColor Gray
}

# ==================== 主程序 ====================
try {
    while ($true) {
        Show-Menu
        $choice = Read-Host "请选择操作"

        switch ($choice) {
            "1" {
                $started = Start-Mihomo
                $proxyOn = Set-Proxy $true
                if ($started -and $proxyOn) {
                    Write-Host "✅ Mihomo 已启动，系统代理已开启" -ForegroundColor Green
                } else {
                    Write-Host "⚠️ 操作可能未完全成功" -ForegroundColor Yellow
                }
                Start-Sleep -Seconds 1
            }
            "2" {
                $stopped = Stop-Mihomo
                $proxyOff = Set-Proxy $false
                if ($stopped -and $proxyOff) {
                    Write-Host "✅ Mihomo 已停止，系统代理已关闭" -ForegroundColor Green
                } else {
                    Write-Host "⚠️ 操作可能未完全成功" -ForegroundColor Yellow
                }
                Start-Sleep -Seconds 1
            }
            "3" {
                $currentOn = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).ProxyEnable -eq 1
                $newState = -not $currentOn
                if (Set-Proxy $newState) {
                    $text = if ($newState) { "开启" } else { "关闭" }
                    Write-Host "✅ 系统代理已$text" -ForegroundColor Green
                } else {
                    Write-Host "⚠️ 切换可能未完全成功" -ForegroundColor Yellow
                }
                Start-Sleep -Seconds 1
            }
            "4" {
                Write-Host "再见！" -ForegroundColor Cyan
                exit
            }
            default {
                Write-Host "❌ 无效输入，请输入 1-4" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
} catch {
    Write-Host "发生错误: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "按回车键退出..."
}
