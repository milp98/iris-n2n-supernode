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
        Write-Host "NSSM �Ѿ�������Ŀ¼����������." -ForegroundColor Green
        return
    } else {
        Write-Host "���ڴӻ�ȡ NSSM..." -ForegroundColor Blue
    }

    try {
        # ���ز���ѹ NSSM
        Invoke-WebRequest -Uri $nssmZipUrl -OutFile $tempZip
        $tempDir = Join-Path $env:TEMP "nssm-extract"
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

        # ����nssm.exe (����64λ��)
        $nssmExePath = Join-Path $tempDir "nssm-${nssmVersion}\win64\nssm.exe"
        if (Test-Path $nssmExePath) {
            Copy-Item -Path $nssmExePath -Destination $scriptDir -Force
        } else {
            # 64λ�����ڳ��Ը���32λ
            $nssmExePath = Join-Path $tempDir "nssm-${nssmVersion}\win32\nssm.exe"
            Copy-Item -Path $nssmExePath -Destination $scriptDir -Force
        }
    } finally {
        # ������ʱ�ļ�
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
        Write-Host "supernode �Ѿ�������Ŀ¼����������." -ForegroundColor Green
        return
    }
    # n2n �汾��������Ϣ
    $n2nUrl, $tempZip = $null, $null
    $N2NReleaseAuthor = "5656565566"
    $ApiURL = "https://api.github.com/repos/$N2NReleaseAuthor/n2n/releases"
    # �����Token�����ֶ���ӵ�����ͷ
    $headers = @{}
    
    if (-not [string]::IsNullOrEmpty($Token)) {
    $headers["Authorization"] = "token $Token"
    }

    try {
        Write-Host "���ڴӻ�ȡGithub��Ŀ$N2NReleaseAuthor/n2n��Releases��Ϣ." -ForegroundColor Cyan
        $response = Invoke-RestMethod -Uri $ApiURL -Headers $headers -ErrorAction Stop
        # ������ʽ�汾����Ԥ������
        $releases = $response | Where-Object { -not $_.prerelease }

        # ���û���ҵ��κΰ汾
        if (-not $releases -or $releases.Count -eq 0) {
            throw "δ�ҵ��κ���ʽ Releases �汾"
            exit
        }

        # ���Ұ��� Windows ����Դ
        $windowsAssets = $releases.assets | Where-Object { 
            $_.name -match "windows" -or $_.browser_download_url -match "windows"
        } | Select-Object *, @{
            Name = "UrlFileName";
            Expression = { Get-FileNameFromUrl -Url $_.browser_download_url }
        }

        if (-not $windowsAssets -or $windowsAssets.Count -eq 0) {
            throw "δ�ҵ�����Windows��������Դ"
            exit
        }

        $windowsAssets | ForEach-Object {
            # $($_.browser_download_url)
            Write-Host "���ҵ��ļ�: $($_.name)" -ForegroundColor Green
            $n2nUrl = $_.browser_download_url
            $tempZip = Join-Path $env:TEMP $_.name
        
            try {
                # ���ز���ѹ n2n
                $null = New-Item -ItemType Directory -Path (Split-Path $tempZip) -Force -ErrorAction SilentlyContinue

                Invoke-WebRequest -Uri $n2nUrl -OutFile $tempZip
                $tempDir = Join-Path $env:TEMP "n2n-extract"
                Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

                # ���Ҳ����� supernode.exe
                $supernodeExe = Get-ChildItem -Path $tempDir -Recurse -Filter "supernode.exe" | Select-Object -First 1
                if ($supernodeExe) {
                    Copy-Item -Path $supernodeExe.FullName -Destination $scriptDir -Force
                } else {
                    throw "ʧ��: �Ҳ���supernode.exe�����ĳ���"
                }
            } catch {
                Write-Error "�����ļ�ʱ����: $($_.Exception.Message)"
                throw
            } finally {
                # ������ʱ�ļ�
                if (Test-Path $tempZip) { 
                    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue 
                }
                if (Test-Path $tempDir) { 
                    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue 
                }
            }
        }
    } catch {
        Write-Error "��ȡ Releases ��Ϣʧ��: $_"
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-Host "�ѳ���GitHub API���ƣ����Ժ�����" -ForegroundColor Yellow
        }
        exit 1
    }
}

function Set-Config {
    # ����IrisN2N������
    $serviceName = "IrisServer"
    $defaultPort = 7654
    $defaultFederation = "Iris"
    $defaultManagementPort = 5656
    $defaultManagementPassword = "Iris-server"
    

    $port = Read-Host "�������˿� (Ĭ��: $defaultPort)"
    if ([string]::IsNullOrWhiteSpace($port)) {
        $port = $defaultPort
    }

    $federation = Read-Host "������������ (Ĭ��: $defaultFederation)"
    if ([string]::IsNullOrWhiteSpace($federation)) {
        $federation = $defaultFederation
    }

    $managementPort = Read-Host "���������˿� (Ĭ��: $defaultManagementPort)"
    if ([string]::IsNullOrWhiteSpace($managementPort)) {
        $managementPort = $defaultManagementPort
    }

    $managementPassword = Read-Host "������������� (Ĭ��: $defaultManagementPassword)" -AsSecureString
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

# д�������ļ�
    try {
        $configPath = "supernode.conf"
        $configContent | Out-File -FilePath $configPath -Encoding UTF8
        Write-Host "д������: $((Get-Item $configPath).FullName)"
    } catch {
        Write-Host "д������ʱ����: $_" -ForegroundColor Red
        exit
    }

    try {
        $NssMExe = Get-ChildItem -Path $tempDir -Recurse -Filter "nssm.exe"
        $UseAdmin = {
            & $scriptDir\$NssMExe install $serviceName "supernode.exe" "$scriptDir\$configPath"
            & $scriptDir\$NssMExe set $serviceName DisplayName "IrisN2N������"
            & $scriptDir\$NssMExe set $serviceName Description "IrisN2N����������"
            & $scriptDir\$NssMExe set $serviceName Start SERVICE_AUTO_START
        }
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile -Command & {$UseAdmin}" -Verb RunAs
        } else {
            Invoke-Command -ScriptBlock $UseAdmin
        }
    
    } catch {
        Write-Host "ִ��ĳһ��ָ��ʱʧ��: $_" -ForegroundColor Red
        Write-Host "���� $serviceName �����Ƿ������Windows������" -ForegroundColor Yellow
        exit 5
    }

    Write-Host "��װIrisN2N���"
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
                Write-Host "�������: $($_.Exception.Message)���������� ($RetryCount/$MaxRetries)..."
                Start-Sleep -Seconds $RetryDelay
            } 
            else {
                Write-Host "�Ѵ���������: $($_.Exception.Message)" -ForegroundColor Red
                exit 3
            }
        }
    } 
}

if (Get-ChildItem -Path $scriptDir -Recurse -Filter "supernode.conf" | Select-Object -First 1) {
    Write-Host "supernode.conf �Ѿ����ڣ����������������ɾ���ļ�"
    exit 7
}

# ���ú���������ִ�е�shell��
Start-InstallerN2N -ScriptBlock {
    Get-NSSM
    Get-n2n
    Set-Config
} -MaxRetries 3 -RetryDelay 5