function Convert-JsonStreamToAdvancedHtml {
    param(
        [string]$JsonStream,
        [string]$Title = "JSON数据表"
    )
    
    $jsonObjects = Invoke-JsonStream $JsonStream
    $tables = @()
    $currentTable = $null
    
    foreach ($jsonObj in $jsonObjects) {
        switch ($jsonObj._type) {
            "begin" {
                $currentTable = @{
                    Caption = $jsonObj.cmd
                    Headers = @()
                    Rows = @()
                }
            }
            
            "row" {
                if ($currentTable) {
                    # 获取属性（排除元数据）
                    $properties = $jsonObj.PSObject.Properties | 
                        Where-Object { $_.Name -notin @('_tag', '_type') }
                    
                    # 设置表头（如果是第一行）
                    if ($currentTable.Headers.Count -eq 0) {
                        $currentTable.Headers = $properties | ForEach-Object { $_.Name }
                    }
                    
                    # 添加行数据
                    $rowData = @{}
                    foreach ($prop in $properties) {
                        $rowData[$prop.Name] = if ($null -eq $prop.Value) { "" } else { $prop.Value }
                    }
                    $currentTable.Rows += $rowData
                }
            }
            
            "end" {
                if ($currentTable) {
                    $tables += $currentTable
                    $currentTable = $null
                }
            }
        }
    }
    
    return Get-AdvancedHtml -Tables $tables -Title $Title
}

function Invoke-JsonStream {
    param([string]$JsonStream)
    
    $objects = @()
    $jsonParts = $JsonStream -split '(?<=\})\s*(?=\{)' | Where-Object { $_.Trim() }
    
    foreach ($part in $jsonParts) {
        try {
            $objects += $part | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $mainLogger.Warning("解析失败: $part")
        }
    }
    
    return $objects
}

function Get-AdvancedHtml {
    param(
        [array]$Tables,
        [string]$Title
    )
    
    $tableHtml = @()
    
    foreach ($table in $Tables) {
        $tableHtml += @"
        <div class="table-section">
            <h2>$($table.Caption)</h2>
            <table>
                <thead>
                    <tr>
                        $(($table.Headers | ForEach-Object {
                            "<th>$_</th>"
                        }) -join "`n                        ")
                    </tr>
                </thead>
                <tbody>
                    $(if ($table.Rows.Count -eq 0) {
                        "<tr><td colspan='$($table.Headers.Count)' class='no-data'>暂无数据</td></tr>"
                    } else {
                        ($table.Rows | ForEach-Object {
                            $row = $_
                            "<tr>$(
                                ($table.Headers | ForEach-Object {
                                    $value = $row[$_]
                                    "<td>$value</td>"
                                }) -join "`n                                "
                            )</tr>"
                        }) -join "`n                    "
                    })
                </tbody>
            </table>
        </div>
"@
    }
    
    return @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$Title</title>
    <style>
        * { box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background-color: #f5f5f5; 
            color: #333; 
        }
        .container { 
            max-width: 1200px; 
            margin: 0 auto; 
            background: white; 
            padding: 30px; 
            border-radius: 10px; 
            box-shadow: 0 2px 10px rgba(0,0,0,0.1); 
        }
        h1 { 
            text-align: center; 
            color: #2c3e50; 
            margin-bottom: 30px; 
            border-bottom: 3px solid #3498db; 
            padding-bottom: 10px; 
        }
        .table-section { 
            margin-bottom: 40px; 
            border: 1px solid #ddd; 
            border-radius: 8px; 
            overflow: hidden; 
        }
        .table-section h2 { 
            background: linear-gradient(135deg, #3498db, #2980b9); 
            color: white; 
            margin: 0; 
            padding: 15px 20px; 
            font-size: 1.2em; 
        }
        table { 
            width: 100%; 
            border-collapse: collapse; 
        }
        th { 
            background-color: #34495e; 
            color: white; 
            padding: 12px 15px; 
            text-align: left; 
            font-weight: 600; 
        }
        td { 
            padding: 10px 15px; 
            border-bottom: 1px solid #ddd; 
        }
        tr:nth-child(even) { 
            background-color: #f8f9fa; 
        }
        tr:hover { 
            background-color: #e3f2fd; 
            transition: background-color 0.2s; 
        }
        .no-data { 
            text-align: center; 
            color: #7f8c8d; 
            font-style: italic; 
            padding: 30px !important; 
        }
        @media (max-width: 768px) {
            .container { padding: 15px; }
            th, td { padding: 8px 10px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>$Title</h1>
        $($tableHtml -join "`n        ")
    </div>
</body>
</html>
"@
}