function Test-DriverVaultAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Confirm-DriverVaultStartup {
    Add-Type -AssemblyName System.Windows.Forms

    $general = [System.Windows.Forms.MessageBox]::Show(
        'Este programa pode precisar de permissoes administrativas para acessar corretamente os drivers de impressora. Deseja continuar?',
        'Permissoes administrativas',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($general -ne [System.Windows.Forms.DialogResult]::Yes) {
        return $false
    }

    if (-not (Test-DriverVaultAdministrator)) {
        $warning = [System.Windows.Forms.MessageBox]::Show(
            'Voce nao esta executando como administrador. Algumas informacoes podem nao ser coletadas corretamente. Deseja continuar mesmo assim?',
            'Administrador recomendado',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return ($warning -eq [System.Windows.Forms.DialogResult]::Yes)
    }

    return $true
}

function Request-DriverVaultElevation {
    Add-Type -AssemblyName System.Windows.Forms

    $answer = [System.Windows.Forms.MessageBox]::Show(
        'A instalacao/restauracao de drivers precisa de permissao de administrador. Deseja reabrir o programa como administrador?',
        'Permissao de administrador necessaria',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return $false
    }

    $state = Get-DriverVaultState
    $scriptPath = Join-Path $state.AppRoot 'DriverVault.ps1'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -STA -File `"{0}`"" -f $scriptPath)
        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            ("Nao foi possivel reabrir como administrador: {0}" -f $_.Exception.Message),
            'Falha na elevacao',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }
}
