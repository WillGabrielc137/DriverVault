# Modulo extraido de MainWindow.ps1.



function Show-DriverVaultMainWindow {
    Initialize-DriverVaultWinForms
    Initialize-DriverVaultDirectories
    $state = Get-DriverVaultState

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'DriverVault - Backup e Restauracao de Drivers de Impressora'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1120, 820)
    $form.MinimumSize = New-Object System.Drawing.Size(980, 730)
    $form.BackColor = Get-ThemeColor '#111827'
    $form.ForeColor = Get-ThemeColor '#E5E7EB'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $title = New-DarkLabel -Text 'Backup e Restauracao de Drivers' -X 18 -Y 14 -Width 520 -Height 32
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::White
    $form.Controls.Add($title)

    $adminLabel = New-DarkLabel -Text '' -X 560 -Y 22 -Width 520 -Height 24
    $adminLabel.TextAlign = 'MiddleRight'
    if (Test-DriverVaultAdministrator) {
        $adminLabel.Text = 'Executando como administrador'
        $adminLabel.ForeColor = Get-ThemeColor '#34D399'
    }
    else {
        $adminLabel.Text = 'Administrador necessario para instalar/restaurar drivers'
        $adminLabel.ForeColor = Get-ThemeColor '#FBBF24'
    }
    $form.Controls.Add($adminLabel)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(20, 58)
    $tabs.Size = New-Object System.Drawing.Size(1060, 570)
    $tabs.Anchor = 'Top, Left, Right, Bottom'
    $tabs.BackColor = Get-ThemeColor '#111827'
    $tabs.ForeColor = Get-ThemeColor '#E5E7EB'

    $backupTab = New-Object System.Windows.Forms.TabPage
    $backupTab.Text = 'Fazer backup dos drivers'
    $backupTab.BackColor = Get-ThemeColor '#111827'
    $backupTab.ForeColor = Get-ThemeColor '#E5E7EB'

    $restoreTab = New-Object System.Windows.Forms.TabPage
    $restoreTab.Text = 'Instalar/restaurar drivers'
    $restoreTab.BackColor = Get-ThemeColor '#111827'
    $restoreTab.ForeColor = Get-ThemeColor '#E5E7EB'

    [void]$tabs.TabPages.Add($backupTab)
    [void]$tabs.TabPages.Add($restoreTab)
    $form.Controls.Add($tabs)

    $statusLabel = New-DarkLabel -Text 'Pronto. Escolha uma aba para fazer backup ou restaurar drivers.' -X 20 -Y 640 -Width 520 -Height 24
    $statusLabel.Anchor = 'Left, Bottom'
    $statusLabel.ForeColor = Get-ThemeColor '#D1D5DB'
    $form.Controls.Add($statusLabel)

    $btnClearLogs = New-DarkButton -Text 'Apagar logs' -X 615 -Y 636 -Width 125 -Color '#7F1D1D'
    $btnClearReports = New-DarkButton -Text 'Apagar relatorios' -X 755 -Y 636 -Width 145 -Color '#7F1D1D'
    $btnDocs = New-DarkButton -Text 'Abrir documentacao' -X 915 -Y 636 -Width 165 -Color '#374151'
    foreach ($button in @($btnClearLogs, $btnClearReports, $btnDocs)) {
        $button.Anchor = 'Right, Bottom'
        $form.Controls.Add($button)
    }

    $alertsLabel = New-DarkLabel -Text 'Alertas e detalhes' -X 20 -Y 672 -Width 240 -Height 22
    $alertsLabel.Anchor = 'Left, Bottom'
    $form.Controls.Add($alertsLabel)

    $alertsBox = New-Object System.Windows.Forms.TextBox
    $alertsBox.Location = New-Object System.Drawing.Point(20, 697)
    $alertsBox.Size = New-Object System.Drawing.Size(1060, 75)
    $alertsBox.Anchor = 'Left, Right, Bottom'
    $alertsBox.Multiline = $true
    $alertsBox.ScrollBars = 'Vertical'
    $alertsBox.ReadOnly = $true
    $alertsBox.BackColor = Get-ThemeColor '#1F2937'
    $alertsBox.ForeColor = Get-ThemeColor '#F9FAFB'
    $alertsBox.BorderStyle = 'FixedSingle'
    $form.Controls.Add($alertsBox)

    $state.Ui = @{
        Form        = $form
        AlertsBox   = $alertsBox
        StatusLabel = $statusLabel
    }

    Add-BackupTabControls -TabPage $backupTab
    Add-RestoreTabControls -TabPage $restoreTab

    $btnClearLogs.Add_Click({
            Invoke-MaintenanceCleanupFromUi `
                -ConfirmationMessage "Deseja realmente apagar todos os logs?`r`nEssa acao nao podera ser desfeita." `
                -CleanupAction { Clear-DriverVaultLogs }
        }.GetNewClosure())

    $btnClearReports.Add_Click({
            Invoke-MaintenanceCleanupFromUi `
                -ConfirmationMessage "Deseja realmente apagar todos os relatorios?`r`nEssa acao nao podera ser desfeita." `
                -CleanupAction { Clear-DriverVaultReports }
        }.GetNewClosure())

    $btnDocs.Add_Click({
            $doc = Join-Path $state.ProjectRoot 'GUIA_USUARIO.md'
            if (-not (Test-Path -LiteralPath $doc)) {
                $doc = Join-Path $state.DocsRoot 'GUIA_USUARIO.md'
            }
            if (-not (Test-Path -LiteralPath $doc)) {
                $doc = Join-Path $state.ProjectRoot 'README.md'
            }
            if (Test-Path -LiteralPath $doc) {
                Start-Process -FilePath $doc
            }
        }.GetNewClosure())

    $form.Add_Shown({
            Add-AlertText 'Aplicacao iniciada. A restauracao instala apenas drivers selecionados pelo usuario.'
            if (-not (Test-DriverVaultAdministrator)) {
                Add-AlertText 'Aviso: a instalacao/restauracao exige reabertura como administrador.'
            }
        }.GetNewClosure())

    [void][System.Windows.Forms.Application]::Run($form)
}
