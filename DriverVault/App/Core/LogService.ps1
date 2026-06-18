function Start-DriverVaultLog {
    param(
        [string]$BackupPath
    )

    Initialize-DriverVaultDirectories
    $state = Get-DriverVaultState
    $server = ConvertTo-SafeFileName -Name (Get-DriverVaultServerName)
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $state.CurrentLogFile = Join-Path $state.LogRoot ("DriverVault_{0}_{1}.log" -f $server, $stamp)
    New-Item -ItemType File -Force -Path $state.CurrentLogFile | Out-Null

    Write-DriverVaultLog 'Inicio da execucao.'
    Write-DriverVaultLog ("Servidor atual: {0}" -f (Get-DriverVaultServerName))
    Write-DriverVaultLog ("Usuario: {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    Write-DriverVaultLog ("Executando como administrador: {0}" -f (Test-DriverVaultAdministrator))
    if ($BackupPath) {
        Write-DriverVaultLog ("Pasta de backup: {0}" -f $BackupPath)
    }
}

function Write-DriverVaultLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $state = Get-DriverVaultState
    if (-not $state.CurrentLogFile) {
        Initialize-DriverVaultDirectories
        $server = ConvertTo-SafeFileName -Name (Get-DriverVaultServerName)
        $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $state.CurrentLogFile = Join-Path $state.LogRoot ("DriverVault_{0}_{1}.log" -f $server, $stamp)
        New-Item -ItemType File -Force -Path $state.CurrentLogFile | Out-Null
    }

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        Add-Content -LiteralPath $state.CurrentLogFile -Value $line -Encoding UTF8
    }
    catch {
        # Falha de log nao deve interromper coleta ou copia.
    }
}

function Get-DriverVaultLogFile {
    $state = Get-DriverVaultState
    return $state.CurrentLogFile
}
