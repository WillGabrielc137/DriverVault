# Modulo extraido de MainWindow.ps1.



function Invoke-CheckDuplicatesFromUi {
    param(
        [string]$RepositoryRoot
    )

    if (-not (Test-Path -LiteralPath $RepositoryRoot)) {
        [System.Windows.Forms.MessageBox]::Show('Selecione uma pasta de destino valida.', 'Pasta invalida', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $state = Get-DriverVaultState
    Set-StatusText 'Verificando duplicidades no repositorio...'
    Add-AlertText ("Verificacao de duplicidade iniciada em: {0}" -f $RepositoryRoot)

    $records = @(Get-ExistingRepositoryRecords -RepositoryRoot $RepositoryRoot)
    if ($state.LastDrivers.Count -gt 0) {
        $records += $state.LastDrivers
    }

    $duplicates = @(Find-DriverDuplicates -Drivers $records)
    $state.LastDuplicates = $duplicates

    if ($duplicates.Count -eq 0) {
        Add-AlertText 'Nenhuma duplicidade encontrada nas pastas analisadas.'
    }
    else {
        Add-AlertText ("Possiveis duplicidades encontradas: {0}" -f $duplicates.Count)
        foreach ($dup in $duplicates) {
            Add-AlertText ("- {0} ({1}) x {2} ({3}) | {4}" -f $dup.DriverReferencia, $dup.VersaoReferencia, $dup.NovoDriver, $dup.NovaVersao, $dup.Motivo)
        }
    }

    Set-StatusText 'Verificacao de duplicidade concluida.'
}

function Add-BackupTabControls {
    param(
        [System.Windows.Forms.TabPage]$TabPage
    )

    $state = Get-DriverVaultState

    $destLabel = New-DarkLabel -Text 'Pasta mae do backup' -X 20 -Y 18 -Width 180
    $TabPage.Controls.Add($destLabel)

    $destText = New-DarkTextBox -X 20 -Y 42 -Width 760 -Text $state.BackupRoot
    $TabPage.Controls.Add($destText)

    $btnSelect = New-DarkButton -Text 'Selecionar pasta' -X 795 -Y 38 -Width 135 -Color '#4B5563'
    $TabPage.Controls.Add($btnSelect)

    $backupNameLabel = New-DarkLabel -Text 'Nome da pasta do backup' -X 20 -Y 79 -Width 210
    $TabPage.Controls.Add($backupNameLabel)

    $defaultName = Resolve-BackupFolderName -RequestedName ''
    $backupNameText = New-DarkTextBox -X 20 -Y 103 -Width 450 -Text $defaultName
    $TabPage.Controls.Add($backupNameText)

    $btnList = New-DarkButton -Text 'Listar drivers' -X 490 -Y 99 -Width 145 -Color '#2563EB'
    $btnSelectAll = New-DarkButton -Text 'Selecionar todos' -X 650 -Y 99 -Width 130 -Color '#374151'
    $btnClearAll = New-DarkButton -Text 'Desmarcar todos' -X 795 -Y 99 -Width 150 -Color '#374151'
    $btnStart = New-DarkButton -Text 'Fazer backup dos selecionados' -X 20 -Y 144 -Width 230 -Color '#059669'
    $btnVerify = New-DarkButton -Text 'Verificar duplicados' -X 265 -Y 144 -Width 155 -Color '#7C3AED'
    $btnOpen = New-DarkButton -Text 'Abrir pasta do backup' -X 435 -Y 144 -Width 175 -Color '#374151'
    $btnGenerateReport = New-DarkButton -Text 'Gerar relatorio' -X 625 -Y 144 -Width 145 -Color '#2563EB'
    $btnReport = New-DarkButton -Text 'Abrir ultimo relatorio' -X 785 -Y 144 -Width 175 -Color '#374151'
    $TabPage.Controls.AddRange(@($btnList, $btnSelectAll, $btnClearAll, $btnStart, $btnVerify, $btnOpen, $btnGenerateReport, $btnReport))

    $filterLabel = New-DarkLabel -Text 'Buscar driver' -X 20 -Y 190 -Width 110
    $filterText = New-DarkTextBox -X 125 -Y 186 -Width 360 -Text ''
    $foundLabel = New-DarkLabel -Text 'Drivers encontrados: 0' -X 510 -Y 190 -Width 210
    $selectedLabel = New-DarkLabel -Text 'Drivers selecionados: 0' -X 735 -Y 190 -Width 220
    $visibleLabel = New-DarkLabel -Text 'Exibindo: 0' -X 955 -Y 190 -Width 125
    $TabPage.Controls.AddRange(@($filterLabel, $filterText, $foundLabel, $selectedLabel, $visibleLabel))

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(805, 216)
    $progress.Size = New-Object System.Drawing.Size(275, 20)
    $progress.Style = 'Continuous'
    $TabPage.Controls.Add($progress)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(20, 245)
    $grid.Size = New-Object System.Drawing.Size(1060, 285)
    $grid.Anchor = 'Top, Left, Right, Bottom'
    Set-DriverGridTheme -Grid $grid
    $grid.ReadOnly = $false
    $grid.EditMode = 'EditOnEnter'
    [void]$grid.Columns.Add('Driver', 'Driver')
    $selectColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $selectColumn.Name = 'Select'
    $selectColumn.HeaderText = ''
    $selectColumn.Width = 45
    $selectColumn.ReadOnly = $false
    $grid.Columns.Insert(0, $selectColumn)
    [void]$grid.Columns.Add('Fabricante', 'Fabricante')
    [void]$grid.Columns.Add('Versao', 'Versao')
    [void]$grid.Columns.Add('Arquitetura', 'Arquitetura')
    [void]$grid.Columns.Add('InfPath', 'INF')
    [void]$grid.Columns.Add('Status', 'Status')
    foreach ($column in $grid.Columns) {
        if ($column.Name -ne 'Select') {
            $column.ReadOnly = $true
        }
    }
    $grid.Columns['Driver'].FillWeight = 190
    $grid.Columns['Fabricante'].FillWeight = 120
    $grid.Columns['Versao'].FillWeight = 90
    $grid.Columns['Arquitetura'].FillWeight = 90
    $grid.Columns['InfPath'].FillWeight = 160
    $grid.Columns['Status'].FillWeight = 120
    $TabPage.Controls.Add($grid)

    $state.Ui.Grid = $grid
    $state.Ui.Progress = $progress
    $state.Ui.DestinationText = $destText
    $state.Ui.BackupNameText = $backupNameText
    $state.Ui.BackupFilterText = $filterText
    $state.Ui.BackupFoundLabel = $foundLabel
    $state.Ui.BackupSelectedLabel = $selectedLabel
    $state.Ui.BackupVisibleLabel = $visibleLabel

    $filterText.Add_TextChanged({
            Update-DriverGrid
        }.GetNewClosure())

    $grid.Add_CurrentCellDirtyStateChanged({
            if ($grid.IsCurrentCellDirty) {
                $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) | Out-Null
            }
        }.GetNewClosure())

    $grid.Add_CellValueChanged({
            param($sender, $eventArgs)
            if ($eventArgs.RowIndex -ge 0 -and $grid.Columns[$eventArgs.ColumnIndex].Name -eq 'Select') {
                $row = $grid.Rows[$eventArgs.RowIndex]
                $driver = $row.Tag
                if ($driver) {
                    $driver.SelectedForBackup = [bool]$row.Cells['Select'].Value
                    if ($driver.SelectedForBackup -and $driver.BackupStatus -ne 'Success' -and $driver.BackupStatus -ne 'Incomplete' -and $driver.BackupStatus -ne 'Failed') {
                        $driver.Status = 'Selecionado'
                    }
                    elseif (-not $driver.SelectedForBackup -and $driver.BackupStatus -ne 'Success' -and $driver.BackupStatus -ne 'Incomplete' -and $driver.BackupStatus -ne 'Failed') {
                        $driver.Status = 'Encontrado'
                    }
                    Update-BackupCounters
                }
            }
        }.GetNewClosure())

    $btnSelect.Add_Click({
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = 'Selecione a pasta mae onde os backups serao salvos'
            $dialog.SelectedPath = $state.Ui.DestinationText.Text
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $state.Ui.DestinationText.Text = $dialog.SelectedPath
            }
        }.GetNewClosure())

    $btnList.Add_Click({
            $buttons = @($btnList, $btnSelectAll, $btnClearAll, $btnStart, $btnVerify, $btnSelect, $btnOpen, $btnGenerateReport, $btnReport)
            try {
                Set-UiControlsEnabled -Controls $buttons -Enabled $false -Stage 'listando drivers para backup'
                Set-StatusText 'Listando drivers instalados...'
                Add-AlertText 'Listagem de drivers instalados iniciada. Nenhum backup sera executado nesta etapa.'
                $state.LastDrivers = @()
                Update-DriverGrid

                $drivers = @(Get-PrinterDriverInventory)
                foreach ($driver in $drivers) {
                    $driver.SelectedForBackup = $false
                    $driver.BackupStatus = 'NotStarted'
                    $driver.IsInstallable = $false
                    $driver.ValidationMessages = @()
                    $driver.Status = 'Encontrado'
                }
                $state.LastDrivers = $drivers
                Update-DriverGrid
                Add-AlertText ("Drivers encontrados para backup: {0}" -f $drivers.Count)
                Write-DriverVaultLog ("Listagem de backup concluida. Total de drivers encontrados: {0}" -f $drivers.Count)
                Set-StatusText 'Drivers carregados. Selecione os drivers para backup.'
            }
            catch {
                Write-DriverVaultLog ("Erro ao listar drivers para backup: {0}" -f $_.Exception.Message) 'ERROR'
                Add-AlertText ("Erro ao listar drivers para backup: {0}" -f $_.Exception.Message)
                Set-StatusText 'Erro ao listar drivers para backup.'
                [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Listagem de backup', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            }
            finally {
                Set-UiControlsEnabled -Controls $buttons -Enabled $true -Stage 'finalizando listagem de backup'
            }
        }.GetNewClosure())

    $btnSelectAll.Add_Click({
            $filter = $state.Ui.BackupFilterText.Text
            foreach ($driver in @($state.LastDrivers | Where-Object { Test-BackupDriverMatchesFilter -Driver $_ -Filter $filter })) {
                $driver.SelectedForBackup = $true
                if ($driver.BackupStatus -ne 'Success' -and $driver.BackupStatus -ne 'Incomplete' -and $driver.BackupStatus -ne 'Failed') {
                    $driver.Status = 'Selecionado'
                }
            }
            Update-DriverGrid
        }.GetNewClosure())

    $btnClearAll.Add_Click({
            foreach ($driver in @($state.LastDrivers)) {
                $driver.SelectedForBackup = $false
                if ($driver.BackupStatus -ne 'Success' -and $driver.BackupStatus -ne 'Incomplete' -and $driver.BackupStatus -ne 'Failed') {
                    $driver.Status = 'Encontrado'
                }
            }
            Update-DriverGrid
        }.GetNewClosure())

    $btnStart.Add_Click({
            $buttons = @($btnList, $btnSelectAll, $btnClearAll, $btnStart, $btnVerify, $btnSelect, $btnOpen, $btnGenerateReport, $btnReport)
            try {
                $selectedDrivers = @(Get-SelectedBackupDrivers)
                if ($state.LastDrivers.Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show('Clique em Listar drivers antes de iniciar o backup.', 'Backup', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                    return
                }
                if ($selectedDrivers.Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show('Selecione pelo menos um driver para backup.', 'Backup', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                    return
                }

                Write-DriverVaultLog ("Total de drivers encontrados na tela de backup: {0}" -f @($state.LastDrivers).Count)
                Write-DriverVaultLog ("Total de drivers selecionados para backup: {0}" -f $selectedDrivers.Count)
                Write-DriverVaultLog ("Drivers nao selecionados ignorados antes da exportacao/copia: {0}" -f (@($state.LastDrivers).Count - $selectedDrivers.Count))

                Set-UiControlsEnabled -Controls $buttons -Enabled $false -Stage 'iniciando backup'
                $candidate = Resolve-BackupFolderSelection -DestinationRoot $state.Ui.DestinationText.Text -BackupFolderName $state.Ui.BackupNameText.Text -BackupNameTextBox $state.Ui.BackupNameText
                if (-not $candidate) {
                    Set-StatusText 'Backup cancelado pelo usuario.'
                    return
                }

                $null = Start-DriverVaultJob `
                    -DestinationRoot $state.Ui.DestinationText.Text `
                    -BackupPath $candidate.Path `
                    -Drivers $selectedDrivers `
                    -AllDriversForManifest $state.LastDrivers `
                    -StatusCallback { param($message) Set-StatusText $message } `
                    -AlertCallback { param($message) Add-AlertText $message } `
                    -GridCallback { param($drivers) Update-DriverGrid -Drivers $drivers } `
                    -ProgressCallback { param($value, $maximum) Update-BackupProgress -Value $value -Maximum $maximum } `
                    -DuplicateDecisionCallback { param($driver, $duplicate) Invoke-DuplicateDecisionDialog -Driver $driver -Duplicado $duplicate } `
                    -SkipDocxReport
            }
            catch {
                Write-DriverVaultLog ("Erro geral no backup: {0}" -f $_.Exception.Message) 'ERROR'
                Add-AlertText ("Erro geral no backup: {0}" -f $_.Exception.Message)
                Set-StatusText 'Backup finalizado com erro.'
                [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Erro no backup', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
            finally {
                Set-UiControlsEnabled -Controls $buttons -Enabled $true -Stage 'finalizando backup'
            }
        }.GetNewClosure())

    $btnVerify.Add_Click({
            try {
                Invoke-CheckDuplicatesFromUi -RepositoryRoot $state.Ui.DestinationText.Text
            }
            catch {
                Add-AlertText ("Erro ao verificar duplicados: {0}" -f $_.Exception.Message)
                Set-StatusText 'Erro ao verificar duplicados.'
            }
        }.GetNewClosure())

    $btnOpen.Add_Click({
            $path = $state.LastBackupPath
            if (-not $path) {
                $path = $state.Ui.DestinationText.Text
            }
            if (Test-Path -LiteralPath $path) {
                Start-Process explorer.exe -ArgumentList ('"{0}"' -f $path)
            }
        }.GetNewClosure())

    $btnGenerateReport.Add_Click({
            try {
                if (-not $state.LastBackupPath -or -not (Test-Path -LiteralPath $state.LastBackupPath -PathType Container)) {
                    [System.Windows.Forms.MessageBox]::Show('Execute ou selecione um backup antes de gerar o relatorio.', 'Relatorio', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                    return
                }
                if (@($state.LastDrivers).Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show('Nao ha dados de drivers carregados para gerar relatorio.', 'Relatorio', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                    return
                }
                $path = New-DriverVaultReport -Drivers $state.LastDrivers -Duplicados $state.LastDuplicates -BackupPath $state.LastBackupPath
                Add-AlertText ("Relatorio gerado em: {0}" -f $path)
                Set-StatusText 'Relatorio gerado.'
                [System.Windows.Forms.MessageBox]::Show("Relatorio gerado em:`r`n$path", 'Relatorio', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            catch {
                $message = "Falha ao gerar relatorio.`r`nCaminho tentado: $($state.ReportRoot)`r`nErro: $($_.Exception.Message)"
                Add-AlertText ($message -replace "`r`n", ' ')
                [System.Windows.Forms.MessageBox]::Show($message, 'Erro no relatorio', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        }.GetNewClosure())

    $btnReport.Add_Click({ Open-LastReport }.GetNewClosure())
}
