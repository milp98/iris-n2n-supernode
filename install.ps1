$scriptDir = $PSScriptRoot
$tempZip = $null
$global:DownloadErrBool = $false
$global:DownloadChina = "YXEucmFpbnBsYXkuY246MjE1MDE="
$ErrorActionPreference = "Stop"

function Get-NSSM {
    $nssmVersion = "2.24"
    $nssmZipUrl = "https://nssm.cc/release/nssm-${nssmVersion}.zip"
    $tempZip = Join-Path $env:TEMP "nssm-${nssmVersion}.zip"

    if (Get-ChildItem -Path $scriptDir -Recurse -Filter "nssm.exe" | Select-Object -First 1) {
        Write-Host "NSSM 已经存在于目录，跳过下载." -ForegroundColor Green
        return
    } else {
        Write-Host "正在从获取 NSSM..." -ForegroundColor Blue
    }

    try {
        # 下载并解压 NSSM
        Invoke-WebRequest -Uri $nssmZipUrl -OutFile $tempZip
        $tempDir = Join-Path $env:TEMP "nssm-extract"
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

        # 复制nssm.exe (优先64位版)
        $nssmExePath = Join-Path $tempDir "nssm-${nssmVersion}\win64\nssm.exe"
        if (Test-Path $nssmExePath) {
            Copy-Item -Path $nssmExePath -Destination $scriptDir -Force
        } else {
            # 64位不存在尝试复制32位
            $nssmExePath = Join-Path $tempDir "nssm-${nssmVersion}\win32\nssm.exe"
            Copy-Item -Path $nssmExePath -Destination $scriptDir -Force
        }
    } finally {
        # 清理临时文件
        if (Test-Path $tempZip) {
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-n2n {
    if (Get-ChildItem -Path $scriptDir -Recurse -Filter "supernode.exe" | Select-Object -First 1) {
        Write-Host "supernode 已经存在于目录，跳过下载." -ForegroundColor Green
        return
    }
    # n2n 版本和作者信息
    $n2nUrl, $tempZip = $null, $null
    $N2NReleaseAuthor = "5656565566"
    $ApiURL = "https://api.github.com/repos/$N2NReleaseAuthor/n2n/releases"
    # 如果有Token，请手动添加到请求头
    $headers = @{}
    
    if (-not [string]::IsNullOrEmpty($Token)) {
    $headers["Authorization"] = "token $Token"
    }

    try {
        Write-Host "正在从获取Github项目$N2NReleaseAuthor/n2n的Releases信息." -ForegroundColor Cyan
        $response = Invoke-RestMethod -Uri $ApiURL -Headers $headers -ErrorAction Stop
        # 过滤正式版本（非预发布）
        $releases = $response | Where-Object { -not $_.prerelease }

        # 如果没有找到任何版本
        if (-not $releases -or $releases.Count -eq 0) {
            throw "未找到任何正式 Releases 版本"
            exit
        }

        # 查找包含 Windows 的资源
        $windowsAssets = $releases.assets | Where-Object { 
            $_.name -match "windows" -or $_.browser_download_url -match "windows"
        } | Select-Object *, @{
            Name = "UrlFileName";
            Expression = { Get-FileNameFromUrl -Url $_.browser_download_url }
        }

        if (-not $windowsAssets -or $windowsAssets.Count -eq 0) {
            throw "未找到包含Windows的下载资源"
            exit
        }

        $windowsAssets | ForEach-Object {
            # $($_.browser_download_url)
            Write-Host "已找到文件: $($_.name)" -ForegroundColor Green
            $n2nUrl = $_.browser_download_url
            $tempZip = Join-Path $env:TEMP $_.name
        
            try {
                # 下载并解压 n2n
                $null = New-Item -ItemType Directory -Path (Split-Path $tempZip) -Force -ErrorAction SilentlyContinue

                Invoke-WebRequest -Uri $n2nUrl -OutFile $tempZip
                $tempDir = Join-Path $env:TEMP "n2n-extract"
                Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

                # 查找并复制 supernode.exe
                $supernodeExe = Get-ChildItem -Path $tempDir -Recurse -Filter "supernode.exe" | Select-Object -First 1
                if ($supernodeExe) {
                    Copy-Item -Path $supernodeExe.FullName -Destination $scriptDir -Force
                } else {
                    throw "失败: 找不到supernode.exe关联的程序"
                }
            } catch {
                Write-Error "处理文件时出错: $($_.Exception.Message)"
                throw
            } finally {
                # 清理临时文件
                if (Test-Path $tempZip) { 
                    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue 
                }
                if (Test-Path $tempDir) { 
                    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue 
                }
            }
        }
    } catch {
        Write-Error "获取 Releases 信息失败: $_"
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-Host "已超出GitHub API限制，请稍后再试" -ForegroundColor Yellow
        }
        exit 1
    }
}

function Set-Config {
    # 配置IrisN2N服务器
    $serviceName = "IrisServer"
    $defaultPort = 7654
    $defaultFederation = "Iris"
    $defaultManagementPort = 5656
    $defaultManagementPassword = "Iris-server"
    

    $port = Read-Host "服务器端口 (默认: $defaultPort)"
    if ([string]::IsNullOrWhiteSpace($port)) {
        $port = $defaultPort
    }

    $federation = Read-Host "输入联邦名称 (默认: $defaultFederation)"
    if ([string]::IsNullOrWhiteSpace($federation)) {
        $federation = $defaultFederation
    }

    $managementPort = Read-Host "请输入管理端口 (默认: $defaultManagementPort)"
    if ([string]::IsNullOrWhiteSpace($managementPort)) {
        $managementPort = $defaultManagementPort
    }

    $managementPassword = Read-Host "请输入管理密码 (默认: $defaultManagementPassword)" -AsSecureString
    $managementPasswordPlain = if ($managementPassword.Length -eq 0) {
        $defaultManagementPassword
    } else {
        [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($managementPassword)
        )
    }

    $configContent = @"
-p=$port
-F=$federation
-t=$managementPort
--management-password=$managementPasswordPlain
"@

# 写入配置文件
    try {
        $configPath = "supernode.conf"
        $configContent | Out-File -FilePath $configPath -Encoding UTF8
        Write-Host "写入配置: $((Get-Item $configPath).FullName)"
    } catch {
        Write-Host "写入配置时出错: $_" -ForegroundColor Red
        exit
    }

    try {
        $NssMExe = Get-ChildItem -Path $tempDir -Recurse -Filter "nssm.exe"
        $UseAdmin = {
            & $scriptDir\$NssMExe install $serviceName "supernode.exe" "$scriptDir\$configPath"
            & $scriptDir\$NssMExe set $serviceName DisplayName "IrisN2N服务器"
            & $scriptDir\$NssMExe set $serviceName Description "IrisN2N服务器核心"
            & $scriptDir\$NssMExe set $serviceName Start SERVICE_AUTO_START
        }
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile -Command & {$UseAdmin}" -Verb RunAs
        } else {
            Invoke-Command -ScriptBlock $UseAdmin
        }
    
    } catch {
        Write-Host "执行某一个指令时失败: $_" -ForegroundColor Red
        Write-Host "请检查 $serviceName 服务是否存在于Windows服务中" -ForegroundColor Yellow
        exit 5
    }

    Write-Host "安装IrisN2N完成"
    exit 0
}

function Start-InstallerN2N {
    param (
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 5
    )

    $RetryCount = 0
    $lastException = $null

    while ($RetryCount -le $MaxRetries) {
        try {
            & $ScriptBlock
            return
        } 
        catch {
            $RetryCount++
            $lastException = $_
            
            if ($RetryCount -lt $MaxRetries) {
                $global:DownloadErrBool = $true
                Write-Host "网络错误: $($_.Exception.Message)，正在重试 ($RetryCount/$MaxRetries)..."
                Start-Sleep -Seconds $RetryDelay
            } 
            else {
                Write-Host "已达重试上限: $($_.Exception.Message)" -ForegroundColor Red
                exit 3
            }
        }
    } 
}

if (Get-ChildItem -Path $scriptDir -Recurse -Filter "supernode.conf" | Select-Object -First 1) {
    Write-Host "supernode.conf 已经存在，如果想重新生成请删除文件"
    exit 7
}

# 调用函数，传入执行的shell块
Start-InstallerN2N -ScriptBlock {
    Get-NSSM
    Get-n2n
    Set-Config
} -MaxRetries 3 -RetryDelay 5