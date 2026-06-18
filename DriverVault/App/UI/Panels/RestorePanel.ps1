# Modulo extraido de MainWindow.ps1.



function Add-RestoreTabControls {
    param(
        [System.Windows.Forms.TabPage]$TabPage
    )

    $state = Get-DriverVaultState

    $restoreLabel = New-DarkLabel -Text 'Pasta de backup para restaurar' -X 20 -Y 18 -Width 240
    $TabPage.Controls.Add($restoreLabel)

    $restoreText = New-DarkTextBox -X 20 -Y 42 -Width 760 -Text $state.BackupRoot
    $TabPage.Controls.Add($restoreText)

    $btnRestoreSelect = New-DarkButton -Text 'Selecionar pasta' -X 795 -Y 38 -Width 135 -Color '#4B5563'
    $btnScan = New-DarkButton -Text 'Localizar drivers' -X 945 -Y 38 -Width 135 -Color '#2563EB'
    $TabPage.Controls.AddRange(@($btnRestoreSelect, $btnScan))

    $btnSelectAll = New-DarkButton -Text 'Selecionar todos' -X 20 -Y 86 -Width 130 -Color '#374151'
    $btnClearAll = New-DarkButton -Text 'Desmarcar todos' -X 165 -Y 86 -Width 150 -Color '#374151'
    $btnInstall = New-DarkButton -Text 'Instalar selecionados' -X 335 -Y 86 -Width 185 -Color '#059669'
    $btnGenerateReport = New-DarkButton -Text 'Gerar relatorio' -X 535 -Y 86 -Width 150 -Color '#2563EB'
    $btnOpenReport = New-DarkButton -Text 'Abrir relatorio' -X 700 -Y 86 -Width 145 -Color '#374151'
    $btnCancelScan = New-DarkButton -Text 'Cancelar listagem' -X 860 -Y 86 -Width 155 -Color '#7F1D1D'
    $btnCancelScan.Enabled = $false
    $TabPage.Controls.AddRange(@($btnSelectAll, $btnClearAll, $btnInstall, $btnGenerateReport, $btnOpenReport, $btnCancelScan))

    $filterLabel = New-DarkLabel -Text 'Buscar driver' -X 20 -Y 126 -Width 110
    $filterText = New-DarkTextBox -X 125 -Y 122 -Width 360 -Text ''
    $foundLabel = New-DarkLabel -Text 'Drivers encontrados: 0' -X 510 -Y 126 -Width 210
    $selectedLabel = New-DarkLabel -Text 'Drivers selecionados: 0' -X 735 -Y 126 -Width 220
    $visibleLabel = New-DarkLabel -Text 'Exibindo: 0' -X 955 -Y 126 -Width 125
    $TabPage.Controls.AddRange(@($filterLabel, $filterText, $foundLabel, $selectedLabel, $visibleLabel))

    $restoreGrid = New-Object System.Windows.Forms.DataGridView
    $restoreGrid.Location = New-Object System.Drawing.Point(20, 165)
    $restoreGrid.Size = New-Object System.Drawing.Size(1060, 365)
    $restoreGrid.Anchor = 'Top, Left, Right, Bottom'
    Set-DriverGridTheme -Grid $restoreGrid
    $restoreGrid.ReadOnly = $false
    $restoreGrid.EditMode = 'EditOnEnter'
    $restoreGrid.Columns.Clear()

    $selectColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $selectColumn.Name = 'Select'
    $selectColumn.HeaderText = ''
    $selectColumn.Width = 45
    $selectColumn.ReadOnly = $false
    [void]$restoreGrid.Columns.Add($selectColumn)
    [void]$restoreGrid.Columns.Add('Driver', 'Driver')
    [void]$restoreGrid.Columns.Add('Fabricante', 'Fabricante')
    [void]$restoreGrid.Columns.Add('Versao', 'Versao')
    [void]$restoreGrid.Columns.Add('Arquitetura', 'Arquitetura')
    [void]$restoreGrid.Columns.Add('Status', 'Status')
    [void]$restoreGrid.Columns.Add('InfPath', 'INF')
    [void]$restoreGrid.Columns.Add('BackupPath', 'Caminho do backup')
    foreach ($column in $restoreGrid.Columns) {
        if ($column.Name -ne 'Select') {
            $column.ReadOnly = $true
        }
    }
    $restoreGrid.Columns['Driver'].FillWeight = 170
    $restoreGrid.Columns['Fabricante'].FillWeight = 100
    $restoreGrid.Columns['Versao'].FillWeight = 70
    $restoreGrid.Columns['Arquitetura'].FillWeight = 70
    $restoreGrid.Columns['Status'].FillWeight = 85
    $restoreGrid.Columns['InfPath'].FillWeight = 180
    $restoreGrid.Columns['BackupPath'].FillWeight = 210
    $TabPage.Controls.Add($restoreGrid)

    $state.Ui.RestoreBackupText = $restoreText
    $state.Ui.RestoreGrid = $restoreGrid
    $state.Ui.RestoreFilterText = $filterText
    $state.Ui.RestoreFoundLabel = $foundLabel
    $state.Ui.RestoreSelectedLabel = $selectedLabel
    $state.Ui.RestoreVisibleLabel = $visibleLabel

    $filterText.Add_TextChanged({
            Update-RestoreGrid
        }.GetNewClosure())

    $restoreGrid.Add_CurrentCellDirtyStateChanged({
            if ($restoreGrid.IsCurrentCellDirty) {
                $restoreGrid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) | Out-Null
            }
        }.GetNewClosure())

    $restoreGrid.Add_CellValueChanged({
            param($sender, $eventArgs)
            if ($eventArgs.RowIndex -ge 0 -and $restoreGrid.Columns[$eventArgs.ColumnIndex].Name -eq 'Select') {
                $row = $restoreGrid.Rows[$eventArgs.RowIndex]
                $driver = $row.Tag
                if ($driver) {
                    $driver.Selected = [bool]$row.Cells['Select'].Value
                    Update-RestoreCounters
                }
            }
        }.GetNewClosure())

    $btnRestoreSelect.Add_Click({
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = 'Selecione a pasta Backups ou uma pasta especifica de backup'
            $dialog.SelectedPath = $state.Ui.RestoreBackupText.Text
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $state.Ui.RestoreBackupText.Text = $dialog.SelectedPath
            }
        }.GetNewClosure())

    $btnScan.Add_Click({
            try {
                $state.RestoreScanCancelRequested = $false
                $btnCancelScan.Enabled = $true
                Set-UiControlsEnabled -Controls @($btnRestoreSelect, $btnScan, $btnSelectAll, $btnClearAll, $btnInstall, $btnGenerateReport, $btnOpenReport) -Enabled $false -Stage 'listando drivers restauraveis'
                Set-StatusText 'Localizando drivers disponiveis no backup...'
                $state.LastRestorableDrivers = @()
                Update-RestoreGrid
                $state.LastRestorableDrivers = @(Get-RestorableDriversFromBackup `
                    -BackupRoot $state.Ui.RestoreBackupText.Text `
                    -MaxRecords $state.RestoreInventoryMaxRecords `
                    -BatchSize $state.RestoreInventoryBatchSize `
                    -ProgressCallback {
                        param($count, $message)
                        Set-StatusText $message
                        if (($count % 250) -eq 0) {
                            Update-RestoreCounters
                        }
                    } `
                    -BatchCallback {
                        param($batch)
                        if (@($state.LastRestorableDrivers).Count -lt $state.RestoreGridMaxRows) {
                            $state.LastRestorableDrivers = @($state.LastRestorableDrivers + @($batch))
                            Update-RestoreGrid
                        }
                    } `
                    -CancelCallback {
                        return [bool]$state.RestoreScanCancelRequested
                    })
                Update-RestoreGrid
                Add-AlertText ("Drivers localizados para restauracao: {0}" -f $state.LastRestorableDrivers.Count)
                Write-DriverVaultLog ("Listagem leve de restauracao concluida. Total de drivers encontrados: {0}" -f $state.LastRestorableDrivers.Count)
                if ($state.RestoreScanCancelRequested) {
                    Set-StatusText 'Listagem cancelada pelo usuario.'
                    Add-AlertText 'Listagem de restauracao cancelada pelo usuario antes da instalacao.'
                    Write-DriverVaultLog 'Listagem de restauracao cancelada pelo usuario antes da instalacao.' 'WARN'
                }
                else {
                    Set-StatusText 'Drivers de backup carregados.'
                }
            }
            catch {
                Add-AlertText ("Erro ao localizar drivers no backup: {0}" -f $_.Exception.Message)
                Set-StatusText 'Erro ao localizar drivers no backup.'
                [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Restauracao', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            }
            finally {
                $btnCancelScan.Enabled = $false
                Set-UiControlsEnabled -Controls @($btnRestoreSelect, $btnScan, $btnSelectAll, $btnClearAll, $btnInstall, $btnGenerateReport, $btnOpenReport) -Enabled $true -Stage 'finalizando listagem de restauracao'
            }
        }.GetNewClosure())

    $btnCancelScan.Add_Click({
            $state.RestoreScanCancelRequested = $true
            Set-StatusText 'Cancelando listagem...'
            Add-AlertText 'Cancelamento solicitado. A listagem vai parar no proximo lote seguro.'
        }.GetNewClosure())

    $btnSelectAll.Add_Click({
            $filter = $state.Ui.RestoreFilterText.Text
            foreach ($driver in @($state.LastRestorableDrivers | Where-Object { Test-RestorableDriverMatchesFilter -Driver $_ -Filter $filter })) {
                $driver.Selected = (-not $driver.IsValidated -or ($driver.InfExists -and $driver.DriverFolderExists -and $driver.MissingFiles.Count -eq 0 -and $driver.Status -ne 'Assinatura invalida'))
            }
            Update-RestoreGrid
        }.GetNewClosure())

    $btnClearAll.Add_Click({
            foreach ($driver in @($state.LastRestorableDrivers)) {
                $driver.Selected = $false
            }
            Update-RestoreGrid
        }.GetNewClosure())

    $btnInstall.Add_Click({
        $buttons = @($btnRestoreSelect, $btnScan, $btnSelectAll, $btnClearAll, $btnInstall, $btnGenerateReport, $btnOpenReport)
            try {
                $selectedDrivers = @(Get-SelectedRestorableDrivers)
                if ($selectedDrivers.Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show('Selecione pelo menos um driver para instalar.', 'Restauracao', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                    return
                }
                Write-DriverVaultLog ("Total de drivers encontrados na tela de restauracao: {0}" -f @($state.LastRestorableDrivers).Count)
                Write-DriverVaultLog ("Total de drivers selecionados para instalacao: {0}" -f $selectedDrivers.Count)
                Write-DriverVaultLog ("Drivers nao selecionados ignorados antes da validacao/instalacao: {0}" -f (@($state.LastRestorableDrivers).Count - $selectedDrivers.Count))

                if (-not (Test-DriverVaultAdministrator)) {
                    if (Request-DriverVaultElevation) {
                        $state.Ui.Form.Close()
                    }
                    else {
                        Set-StatusText 'Restauracao cancelada: administrador necessario.'
                    }
                    return
                }

                Set-UiControlsEnabled -Controls $buttons -Enabled $false -Stage 'iniciando restauracao'
                if (-not (Get-DriverVaultLogFile)) {
                    Start-DriverVaultLog -BackupPath $state.Ui.RestoreBackupText.Text
                }

                Start-DriverRestoreJob `
                    -Drivers $selectedDrivers `
                    -StatusCallback { param($message) Set-StatusText $message } `
                    -AlertCallback { param($message) Add-AlertText $message } `
                    -GridCallback { Update-RestoreGrid } `
                    -DecisionCallback { param($backupDriver, $installedDriver) Invoke-RestoreConflictDialog -BackupDriver $backupDriver -InstalledDriver $installedDriver } `
                    -CertificateDecisionCallback { param($backupDriver, $diagnostics, $certificatePath) Invoke-CertificateTrustDialog -BackupDriver $backupDriver -Diagnostics $diagnostics -CertificatePath $certificatePath }
            }
            catch {
                Write-DriverVaultLog ("Erro geral na restauracao: {0}" -f $_.Exception.Message) 'ERROR'
                Add-AlertText ("Erro geral na restauracao: {0}" -f $_.Exception.Message)
                Set-StatusText 'Restauracao finalizada com erro.'
                [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Erro na restauracao', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
            finally {
            Set-UiControlsEnabled -Controls $buttons -Enabled $true -Stage 'finalizando restauracao'
        }
    }.GetNewClosure())

    $btnGenerateReport.Add_Click({
        try {
            if (@($state.LastRestorableDrivers).Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show('Localize drivers de um backup antes de gerar o relatorio.', 'Relatorio', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                return
            }
            $null = Get-SelectedRestorableDrivers
            $path = New-DriverRestoreReport -Drivers $state.LastRestorableDrivers -BackupPath $state.Ui.RestoreBackupText.Text -Action 'Restauracao'
            Add-AlertText ("Relatorio de restauracao gerado em: {0}" -f $path)
            Set-StatusText 'Relatorio de restauracao gerado.'
            [System.Windows.Forms.MessageBox]::Show("Relatorio gerado em:`r`n$path", 'Relatorio', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            $message = "Falha ao gerar relatorio.`r`nCaminho tentado: $($state.ReportRoot)`r`nErro: $($_.Exception.Message)"
            Add-AlertText ($message -replace "`r`n", ' ')
            [System.Windows.Forms.MessageBox]::Show($message, 'Erro no relatorio', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    }.GetNewClosure())

    $btnOpenReport.Add_Click({ Open-LastReport }.GetNewClosure())
}
