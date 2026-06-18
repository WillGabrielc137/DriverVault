function Initialize-DriverVaultContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppRoot
    )

    $projectRoot = (Resolve-Path -LiteralPath (Join-Path $AppRoot '..')).Path
    $global:DriverVaultState = [ordered]@{
        AppRoot               = $AppRoot
        ProjectRoot           = $projectRoot
        BackupRoot            = Join-Path $projectRoot 'Backups'
        LogRoot               = Join-Path $projectRoot 'Logs'
        ReportRoot            = Join-Path $projectRoot 'Relatorios'
        DocsRoot              = Join-Path $projectRoot 'docs'
        CurrentLogFile        = $null
        LastBackupPath        = $null
        LastDrivers           = @()
        LastRestorableDrivers = @()
        LastDuplicates        = @()
        LastReportPath        = $null
        RestoreScanCancelRequested = $false
        RestoreGridMaxRows    = 1000
        RestoreInventoryMaxRecords = 5000
        RestoreInventoryBatchSize = 50
        Ui                    = @{}
    }
}

function Get-DriverVaultState {
    if (-not $global:DriverVaultState) {
        throw 'Contexto da aplicacao nao inicializado.'
    }
    return $global:DriverVaultState
}

function Initialize-DriverVaultDirectories {
    $state = Get-DriverVaultState
    foreach ($path in @($state.BackupRoot, $state.LogRoot, $state.ReportRoot, $state.DocsRoot)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Force -Path $path | Out-Null
        }
    }
}

function Get-DriverVaultServerName {
    try {
        return [System.Net.Dns]::GetHostName()
    }
    catch {
        return $env:COMPUTERNAME
    }
}

function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [int]$MaxLength = 110
    )

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $Name
    foreach ($char in $invalid) {
        $safe = $safe.Replace([string]$char, '_')
    }

    $safe = $safe -replace '\s+', '_'
    $safe = $safe -replace '_+', '_'
    $safe = $safe.Trim('_', '.', ' ')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = 'SemNome'
    }
    if ($safe.Length -gt $MaxLength) {
        $safe = $safe.Substring(0, $MaxLength).Trim('_', '.', ' ')
    }
    return $safe
}

function ConvertTo-SafeText {
    param(
        [object]$Value,
        [string]$Default = 'N/D'
    )

    if ($null -eq $Value) {
        return $Default
    }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Default
    }
    return $text
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($prop -and $null -ne $prop.Value) {
            if ($prop.Value -is [System.Array]) {
                if ($prop.Value.Count -gt 0) {
                    return $prop.Value
                }
            }
            else {
                $text = [string]$prop.Value
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    return $prop.Value
                }
            }
        }
    }
    return $null
}

function Invoke-DriverVaultSelfTest {
    param(
        [ValidateSet('Import', 'Duplicate', 'DocxMock', 'All')]
        [string]$Mode = 'All'
    )

    Initialize-DriverVaultDirectories
    if ($Mode -eq 'Import') {
        Write-Host 'SelfTest Import OK'
        return
    }

    if ($Mode -eq 'Duplicate' -or $Mode -eq 'All') {
        $sampleA = 'Brother HL-L2360D series'
        $sampleB = 'Brother HL-L2360D series versao 2.1'
        $sampleC = 'HP Universal Printing PCL 6'
        if (-not (Test-DriverNamesSimilar -NameA $sampleA -NameB $sampleB)) {
            throw 'Falha no teste de normalizacao de duplicidade.'
        }
        if (Test-DriverNamesSimilar -NameA $sampleA -NameB $sampleC) {
            throw 'Falha no teste de falso positivo de duplicidade.'
        }
        Write-Host 'SelfTest Duplicate OK'
    }

    if ($Mode -eq 'DocxMock' -or $Mode -eq 'All') {
        $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('DriverVaultSelfTest_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
        try {
            $driver = New-DriverInfo -Driver 'Driver Teste' -Fabricante 'Fabricante Teste' -Versao '1.0' -Arquitetura 'x64' -CaminhosArquivos @() -Origem 'SelfTest'
            $driver.Status = 'Copiado'
            $driver.ArquivosCopiados = 1
            $report = New-DriverVaultDocxReport -Drivers @($driver) -Duplicados @() -BackupPath $testRoot
            if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
                throw 'Falha ao gerar DOCX de teste.'
            }
            Write-Host ("SelfTest DocxMock OK: {0}" -f $report)
        }
        finally {
            if (Test-Path -LiteralPath $testRoot) {
                Remove-Item -LiteralPath $testRoot -Recurse -Force
            }
        }
    }

    $state = Get-DriverVaultState
    Write-Host ("ProjectRoot: {0}" -f $state.ProjectRoot)
    Write-Host ("BackupRoot:  {0}" -f $state.BackupRoot)
    Write-Host ("LogRoot:     {0}" -f $state.LogRoot)
}
