param(
    [switch]$SelfTest,
    [ValidateSet('Import', 'Duplicate', 'DocxMock', 'All')]
    [string]$SelfTestMode = 'Import',
    [switch]$NoGuiError
)

# Inicializador da aplicacao. A regra de negocio fica nos servicos em App\Core
# e a interface fica em App\UI.

try {
    $requiredScripts = @(
        'Core\AppContext.ps1',
        'Core\AdminService.ps1',
        'Core\LogService.ps1',
        'Models\DuplicateDriver.ps1',
        'Models\DriverInfo.ps1',
        'Models\BackupResult.ps1',
        'Models\RestorableDriver.ps1',
        'Core\DuplicateService.ps1',
        'Core\DriverService.ps1',
        'Core\SignatureService.ps1',
        'Core\MaintenanceService.ps1',
        'Core\RestoreService.ps1',
        'Core\ReportService.ps1',
        'Core\BackupService.ps1',
        'UI\ThemeService.ps1',
        'UI\DialogService.ps1',
        'UI\MainWindow.ps1'
    )

    foreach ($relativePath in $requiredScripts) {
        $path = Join-Path $PSScriptRoot $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Arquivo obrigatorio nao encontrado: $path"
        }
        . $path
    }

    Initialize-DriverVaultContext -AppRoot $PSScriptRoot
    Initialize-DriverVaultDirectories

    if ($SelfTest) {
        Invoke-DriverVaultSelfTest -Mode $SelfTestMode
        return
    }

    if (Confirm-DriverVaultStartup) {
        Show-DriverVaultMainWindow
    }
}
catch {
    $message = "Erro geral ao iniciar o DriverVault: {0}" -f $_.Exception.Message
    if ($SelfTest -or $NoGuiError -or -not [Environment]::UserInteractive) {
        Write-Error $message
    }
    else {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show(
                $message,
                'DriverVault',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        catch {
            Write-Error $message
        }
    }
    exit 1
}
