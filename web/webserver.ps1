# 备注: 此模块为测试管理模块！
# 如果你使用了这个模块，请务必知道这套代码非常的不稳定多人使用可能会崩溃。
# 请以管理员身份运行
# 载入模块
Import-Module ".\log.ps1" -Force -ErrorAction Stop
Import-Module ".\json2html.ps1" -Force -ErrorAction Stop

# 初始化启动参数
$port = 8080
$url = "http://+:$port/" # 网站绑定
$udpHost = "127.0.0.1"           # N2N 管理地址
$udpPort = 5656                  # N2N 管理端口

# 注册CTRL+C处理
$serverRunning = $true
[Console]::TreatControlCAsInput = $false
$cancelEvent = [System.Threading.ManualResetEvent]::new($false)
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $serverRunning = $false
    $cancelEvent.Set()
    $mainLogger.Info("收到退出信号，正在关闭服务器...")
}

# 认证配置
$loginConfigFile = "login-config.json"
$sessionTokens = @{}  # 内存中存储会话令牌
$sessionTimeout = 60*60  # 会话超时时间（秒）

# 注册日记系统
Initialize-Logging -LogDir ".\Logs" -MinLevel INFO  # 日记存放路径跟等级
Get-LogStats -$DaysOld 7                            # 日记保留时间
$mainLogger = [LoggerManager]::GetLogger("IrisWeb")
# 打印开始提示
$mainLogger.Info("IrisN2N Web服务器")
$mainLogger.Info("端口: $port")

function Test-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 加载登录配置
function Load-LoginConfig {
    if (Test-Path $loginConfigFile) {
        try {
            $config = Get-Content $loginConfigFile -Raw | ConvertFrom-Json
            return $config
        } catch {
            $mainLogger.Error("加载登录配置文件失败: $($_.Exception.Message)")
            return $null
        }
    } else {
        $mainLogger.Warning("登录配置文件不存在: $loginConfigFile")
        return $null
    }
}

# 验证用户凭据
function Test-UserCredentials {
    param($username, $password)
    
    $config = Load-LoginConfig
    if ($config -eq $null) {
        return $false
    }
    
    foreach ($user in $config.users) {
        if ($user.username -eq $username -and $user.password -eq $password) {
            return $true
        }
    }
    
    return $false
}

# 生成会话令牌
function New-SessionToken {
    return [System.Guid]::NewGuid().ToString()
}

# 验证会话令牌
function Test-SessionToken {
    param($token)
    
    if (-not $sessionTokens.ContainsKey($token)) {
        return $false
    }
    
    $session = $sessionTokens[$token]
    $currentTime = Get-Date
    
    # 检查会话是否过期
    if (($currentTime - $session.LastActivity).TotalSeconds -gt $sessionTimeout) {
        $sessionTokens.Remove($token)
        $mainLogger.Info("会话过期: $token")
        return $false
    }
    
    # 更新最后活动时间
    $session.LastActivity = $currentTime
    return $true
}

# 从请求中获取Cookie
function Get-CookieFromRequest {
    param($request)
    
    $cookieHeader = $request.Headers["Cookie"]
    if (-not $cookieHeader) {
        return $null
    }
    
    $cookies = @{}
    $cookiePairs = $cookieHeader -split ';'
    
    foreach ($pair in $cookiePairs) {
        $parts = $pair.Trim() -split '=', 2
        if ($parts.Count -eq 2) {
            $cookies[$parts[0]] = $parts[1]
        }
    }
    
    return $cookies
}

# 检查认证
function Test-Authentication {
    param($request)
    
    $cookies = Get-CookieFromRequest $request
    if (-not $cookies -or -not $cookies.ContainsKey("Slogin")) {
        return $false
    }
    
    $token = $cookies["Slogin"]
    return Test-SessionToken $token
}

function Invoke-UDPNet {
    param(
        [string]$Server = $udpHost,
        [int]$Port = $port,
        [string]$Message = "r web edges",
        [int]$Timeout = 5000 # 5秒
    )
    
    # 创建UDP客户端
    $udpClient = New-Object System.Net.Sockets.UdpClient
    $udpClient.Client.ReceiveTimeout = $Timeout
    
    try {
        # 设置远程端口
        $remoteEndpoint = New-Object System.Net.IPEndPoint(
            [System.Net.IPAddress]::Parse($Server), 
            $Port
        )
        
        # 发送消息
        $sendBytes = [System.Text.Encoding]::ASCII.GetBytes($Message)
        $bytesSent = $udpClient.Send($sendBytes, $sendBytes.Length, $remoteEndpoint)
        $mainLogger.Info("发送:$Message 共'$bytesSent'字节")
        
        # 等待响应
        $responseEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $completeResponse = @()

        do {
            try {
                $responseBytes = $udpClient.Receive([ref]$responseEndpoint)
                $responseMessage = [System.Text.Encoding]::ASCII.GetString($responseBytes)
                $completeResponse += $responseMessage
            } catch [System.Net.Sockets.SocketException] {
                if ($_.Exception.SocketErrorCode -eq 'TimedOut') {
                    break
                }
            }
        } while ($true)

        $completeResponse = $completeResponse | ForEach-Object { $_.Trim() }
        
        return $completeResponse
        
    } catch [System.Net.Sockets.SocketException] {
        if ($_.Exception.SocketErrorCode -eq 'TimedOut') {
            $mainLogger.Warning("服务器在 ${Timeout}ms 无响应")
        } else {
            $mainLogger.Warning("网络错误: $($_.Exception.Message)")
        }
    } catch {
        $mainLogger.Error("错误: $($_.Exception.Message)")
    } finally {
        $udpClient.Close()
    }
}

# 定义命令执行函数
function Invoke-CommandType {
    param($commandType)
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $isValidCommand = $false
    $result = ""
    $ChromeSp = @("supernodes", "edges", "communities", "reload_communities", "timestamps", "Packetstats", "verbose")

    foreach ($item in $ChromeSp) {
        if (($commandType.ToLower() -eq $item)) {
            $isValidCommand = $true
            break
        }
    }

    if (!($isValidCommand)) {
        # 非法命令
        $result = "[$timestamp]: 非法请求: $commandType`n"
        $mainLogger.Info("非法请求: $commandType")
        return $result
    }

    [string]$commandInput = 'r web ' + $commandType.ToLower()
    $json = Invoke-UDPNet -Server $udpHost -Port $udpPort -Message $commandInput -Timeout 3000
    $htmlContent = Convert-JsonStreamToAdvancedHtml -JsonStream $json -Title "IrisN2N"
    $response.ContentType = "text/html; charset=utf-8"
    return $htmlContent
}

# 创建HTTP监听器
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
$listener.Start()

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        
        $requestUrl = $request.Url.LocalPath.Trim('/')
        $response.ContentType = "text/plain; charset=utf-8"
        $remoteip = $request.RemoteEndPoint.Address.ToString()

        # 处理认证相关请求
        if ($requestUrl -eq "login" -and $request.HttpMethod -eq "POST") {
            # 处理登录请求
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()
            
            try {
                $loginData = $body | ConvertFrom-Json
                if (Test-UserCredentials $loginData.username $loginData.password) {
                    $token = New-SessionToken
                    $sessionTokens[$token] = @{
                        Username = $loginData.username
                        LastActivity = Get-Date
                    }
                    
                    # 设置Cookie
                    $response.Headers.Add("Set-Cookie", "Slogin=$token; Path=/; HttpOnly")
                    $response.StatusCode = 200
                    $mainLogger.Info("用户登录成功: $($loginData.username)")
                } else {
                    $response.StatusCode = 401
                    $responseBuffer = [System.Text.Encoding]::UTF8.GetBytes("认证失败")
                    $response.ContentLength64 = $responseBuffer.Length
                    $response.OutputStream.Write($responseBuffer, 0, $responseBuffer.Length)
                    $mainLogger.Warning("登录失败: $($loginData.username)")
                }
            } catch {
                $response.StatusCode = 400
                $responseBuffer = [System.Text.Encoding]::UTF8.GetBytes("无效的请求")
                $response.ContentLength64 = $responseBuffer.Length
                $response.OutputStream.Write($responseBuffer, 0, $responseBuffer.Length)
            }
            
            $response.Close()
            continue
        }
        
        if ($requestUrl -eq "check-auth") {
            # 检查认证状态
            if (Test-Authentication $request) {
                $response.StatusCode = 200
            } else {
                $response.StatusCode = 401
            }
            $response.Close()
            continue
        }
        
        if ($requestUrl -eq "logout") {
            # 注销
            $cookies = Get-CookieFromRequest $request
            if ($cookies -and $cookies.ContainsKey("Slogin")) {
                $token = $cookies["Slogin"]
                if ($sessionTokens.ContainsKey($token)) {
                    $sessionTokens.Remove($token)
                    $mainLogger.Info("用户注销: $token")
                }
            }
            
            # 清除Cookie
            $response.Headers.Add("Set-Cookie", "Slogin=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
            $response.Redirect("/login.html")
            $response.Close()
            continue
        }
        
        if ($requestUrl -eq "favicon.ico") {
            $mainLogger.info("丢弃favicon.ico请求")
            $response.StatusCode = 404
            $response.Close()
            continue
        } else {
            $mainLogger.info("收到请求: $remoteip -> /$requestUrl")
        }

        # 检查认证
        if (-not (Test-Authentication $request)) {
            if ($requestUrl -eq "login.html" -or $requestUrl -eq "") {
                # 允许访问登录页面
                if (Test-Path "login.html" -PathType Leaf) {
                    $content = Get-Content "login.html" -Raw -Encoding UTF8
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                    $response.ContentType = "text/html; charset=utf-8"
                } else {
                    $errorMsg = "错误: 找不到login.html文件"
                    $mainLogger.Error("找不到login.html文件")
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errorMsg)
                }
            } else {
                # 重定向到登录页面
                $response.Redirect("/login.html")
                $response.Close()
                continue
            }
        } else {
            # 已认证的用户
            if ($requestUrl -eq "" -or $requestUrl -eq "index.html") {
                # 返回主页面
                if (Test-Path "index.html" -PathType Leaf) {
                    $content = Get-Content "index.html" -Raw -Encoding UTF8
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                    $response.ContentType = "text/html; charset=utf-8"
                } else {
                    $errorMsg = "错误: 找不到index.html文件"
                    $mainLogger.Error("找不到index.html文件")
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errorMsg)
                }
            } else {
                # 执行相应命令
                $commandResult = Invoke-CommandType $requestUrl
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($commandResult)
            }
        }

        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()

        $mainLogger.info("响应完成")
    }
}
catch {
    $mainLogger.Critical("服务器发生致命错误: $($_.Exception.Message)")
}
finally {
    $listener.Stop()
    $listener.Close()
    $mainLogger.Error("程序已崩溃!")
}