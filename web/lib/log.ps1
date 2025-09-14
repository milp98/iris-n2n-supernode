enum LogLevel {
    DEBUG
    INFO
    WARNING
    ERROR
    CRITICAL
}

class Logger {
    [string]$Name
    [LogLevel]$MinLevel = [LogLevel]::INFO
    [string]$LogDir = ".\Logs"
    [int]$MaxFileSizeMB = 10
    [int]$MaxBackupFiles = 5
    [bool]$EnableConsole = $true
    [bool]$EnableFile = $true
    [bool]$EnableColors = $true
    [hashtable]$ColorMap = @{}
    [System.Collections.Queue]$RecentLogs = [System.Collections.Queue]::new(100)
    
    Logger([string]$Name) {
        $this.Name = $Name
        $this.InitializeColorMap()
        $this.EnsureLogDirectory()
    }
    
    [void] InitializeColorMap() {
        $this.ColorMap = @{
            [LogLevel]::DEBUG    = "Gray"
            [LogLevel]::INFO     = "Green"
            [LogLevel]::WARNING  = "Yellow"
            [LogLevel]::ERROR    = "Red"
            [LogLevel]::CRITICAL = "Magenta"
        }
    }
    
    [void] EnsureLogDirectory() {
        if (-not (Test-Path $this.LogDir)) {
            New-Item -Path $this.LogDir -ItemType Directory -Force | Out-Null
        }
    }
    
    [string] GetCurrentLogFile() {
        $dateStamp = Get-Date -Format "yyyyMMdd"
        return Join-Path $this.LogDir "$($this.Name)_$dateStamp.log"
    }
    
    [void] RotateLogFiles() {
        $currentFile = $this.GetCurrentLogFile()
        if (Test-Path $currentFile) {
            $file = Get-Item $currentFile
            if ($file.Length -gt ($this.MaxFileSizeMB * 1MB)) {
                $backupFiles = Get-ChildItem $this.LogDir -Filter "$($this.Name)_*.log" | Sort-Object LastWriteTime -Descending
                
                if ($backupFiles.Count -ge $this.MaxBackupFiles) {
                    $filesToDelete = $backupFiles | Select-Object -Skip $this.MaxBackupFiles
                    foreach ($fileToDelete in $filesToDelete) {
                        Remove-Item $fileToDelete.FullName -Force
                    }
                }
                
                $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
                $newName = "$($this.Name)_$timestamp.log"
                Rename-Item $currentFile (Join-Path $this.LogDir $newName)
            }
        }
    }
    
    [string] FormatLogMessage([LogLevel]$Level, [string]$Message, [string]$Component) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.ff"
        $levelStr = $Level.ToString()  #.PadRight(6)
        $componentStr = if ($Component) { "[$Component] " } else { "" }
        
        return "<$timestamp> [$levelStr]: $componentStr$Message"
    }
    
    [void] WriteLog([LogLevel]$Level, [string]$Message, [string]$Component, [Exception]$Exception) {
        if ($Level -lt $this.MinLevel) { return }
        
        #     쳣  Ϣ
        $fullMessage = $Message
        if ($Exception) {
            $fullMessage += " | Exception: $($Exception.Message) | StackTrace: $($Exception.StackTrace)"
        }
        
        $formattedMessage = $this.FormatLogMessage($Level, $fullMessage, $Component)
        
        #   ӵ      ־    
        $this.RecentLogs.Enqueue($formattedMessage)
        if ($this.RecentLogs.Count -gt 100) {
            $this.RecentLogs.Dequeue()
        }
        
        #     ̨   
        if ($this.EnableConsole) {
            $color = if ($this.EnableColors) { $this.ColorMap[$Level] } else { "White" }
            Write-Host $formattedMessage -ForegroundColor $color
        }
        
        #  ļ    
        if ($this.EnableFile) {
            $this.RotateLogFiles()
            $logFile = $this.GetCurrentLogFile()
            try {
                Add-Content -Path $logFile -Value $formattedMessage -Encoding UTF8
            }
            catch {
                Write-Host " ޷ д    ־ ļ : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    
    #       ־    
    [void] Debug([string]$Message, [string]$Component) {
        $this.WriteLog([LogLevel]::DEBUG, $Message, $Component, $null)
    }
    
    [void] Info([string]$Message, [string]$Component) {
        $this.WriteLog([LogLevel]::INFO, $Message, $Component, $null)
    }
    
    [void] Warning([string]$Message, [string]$Component) {
        $this.WriteLog([LogLevel]::WARNING, $Message, $Component, $null)
    }
    
    [void] Error([string]$Message, [string]$Component, [Exception]$Exception) {
        $this.WriteLog([LogLevel]::ERROR, $Message, $Component, $Exception)
    }
    
    [void] Critical([string]$Message, [string]$Component, [Exception]$Exception) {
        $this.WriteLog([LogLevel]::CRITICAL, $Message, $Component, $Exception)
    }
    
    #   ݷ   
    [void] Debug([string]$Message) { $this.Debug($Message, $null) }
    [void] Info([string]$Message) { $this.Info($Message, $null) }
    [void] Warning([string]$Message) { $this.Warning($Message, $null) }
    [void] Error([string]$Message) { $this.Error($Message, $null, $null) }
    [void] Error([string]$Message, [Exception]$Exception) { $this.Error($Message, $null, $Exception) }
    [void] Critical([string]$Message) { $this.Critical($Message, $null, $null) }
    [void] Critical([string]$Message, [Exception]$Exception) { $this.Critical($Message, $null, $Exception) }
    
    #    ߷   
    [array] GetRecentLogs([int]$Count = 20) {
        return $this.RecentLogs.ToArray() | Select-Object -Last $Count
    }
    
    [void] ClearRecentLogs() {
        $this.RecentLogs.Clear()
    }
    
    [string] GetLogStatistics() {
        $stats = @{
            TotalRecentLogs = $this.RecentLogs.Count
            LogDirectory    = $this.LogDir
            CurrentLevel    = $this.MinLevel.ToString()
            ConsoleEnabled  = $this.EnableConsole
            FileEnabled     = $this.EnableFile
        }
        return ($stats | ConvertTo-Json -Compress)
    }
}

class LoggerManager {
    static [hashtable]$Loggers = @{}
    static [string]$DefaultLogDir = ".\Logs"
    
    static [Logger] GetLogger([string]$Name) {
        if (-not [LoggerManager]::Loggers.ContainsKey($Name)) {
            $logger = [Logger]::new($Name)
            $logger.LogDir = [LoggerManager]::DefaultLogDir
            [LoggerManager]::Loggers[$Name] = $logger
        }
        return [LoggerManager]::Loggers[$Name]
    }
    
    static [void] ConfigureAll([hashtable]$Configuration) {
        foreach ($logger in [LoggerManager]::Loggers.Values) {
            if ($Configuration.ContainsKey("MinLevel")) {
                $logger.MinLevel = $Configuration.MinLevel
            }
            if ($Configuration.ContainsKey("EnableConsole")) {
                $logger.EnableConsole = $Configuration.EnableConsole
            }
            if ($Configuration.ContainsKey("EnableFile")) {
                $logger.EnableFile = $Configuration.EnableFile
            }
            if ($Configuration.ContainsKey("LogDir")) {
                $logger.LogDir = $Configuration.LogDir
                $logger.EnsureLogDirectory()
            }
        }
    }
    
    static [void] FlushAll() {
        foreach ($logger in [LoggerManager]::Loggers.Values) {
            $logger.ClearRecentLogs()
        }
    }
}

function Initialize-Logging {
    param(
        [string]$LogDir = ".\Logs",
        [LogLevel]$MinLevel = [LogLevel]::INFO,
        [bool]$EnableConsole = $true,
        [bool]$EnableFile = $true
    )
    
    [LoggerManager]::DefaultLogDir = $LogDir
    $config = @{
        MinLevel      = $MinLevel
        EnableConsole = $EnableConsole
        EnableFile    = $EnableFile
        LogDir        = $LogDir
    }
    [LoggerManager]::ConfigureAll($config)
}

function Get-LogStats {
    param([string]$LoggerName = "*")
    
    $loggers = if ($LoggerName -eq "*") {
        [LoggerManager]::Loggers.Values
    } else {
        @([LoggerManager]::GetLogger($LoggerName))
    }
    
    foreach ($logger in $loggers) {
        continue
    }
}

function Clear-OldLogs {
    param(
        [int]$DaysOld = 30,
        [string]$LogDir = ".\Logs"
    )
    
    $cutoffDate = (Get-Date).AddDays(-$DaysOld)
    $oldFiles = Get-ChildItem $LogDir -Filter "*.log" | Where-Object { $_.LastWriteTime -lt $cutoffDate }
    
    if ($oldFiles.Count -gt 0) {
        $oldFiles | Remove-Item -Force
        Write-Host "       $($oldFiles.Count)       ־ ļ " -ForegroundColor Green
    } else {
        Write-Host "û   ҵ     $DaysOld   ľ   ־ ļ " -ForegroundColor Yellow
    }
}