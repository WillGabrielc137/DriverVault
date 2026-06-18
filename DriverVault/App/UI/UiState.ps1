# Modulo extraido de MainWindow.ps1.



function Add-AlertText {
    param(
        [string]$Message
    )

    $state = Get-DriverVaultState
    if ($state.Ui.ContainsKey('AlertsBox') -and $state.Ui.AlertsBox) {
        $state.Ui.AlertsBox.AppendText($Message + [Environment]::NewLine)
        $state.Ui.AlertsBox.SelectionStart = $state.Ui.AlertsBox.Text.Length
        $state.Ui.AlertsBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Set-UiControlsEnabled {
    param(
        [object[]]$Controls,
        [bool]$Enabled,
        [string]$Stage = 'atualizando interface'
    )

    foreach ($control in @($Controls)) {
        if ($control -is [System.Windows.Forms.Control]) {
            $control.Enabled = $Enabled
            continue
        }

        $typeName = if ($null -eq $control) { '<null>' } else { $control.GetType().FullName }
        Write-DriverVaultLog ("Objeto ignorado ao alterar Enabled em {0}. Tipo: {1}" -f $Stage, $typeName) 'WARN'
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-StatusText {
    param(
        [string]$Message
    )

    $state = Get-DriverVaultState
    if ($state.Ui.ContainsKey('StatusLabel') -and $state.Ui.StatusLabel) {
        $state.Ui.StatusLabel.Text = $Message
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Get-BackupDriverInfDisplay {
    param(
        [object]$Driver
    )

    $names = @()
    foreach ($property in @('OriginalInfName', 'PublishedName')) {
        $value = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @($property)) -Default ''
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $names += [System.IO.Path]::GetFileName($value)
        }
    }

    $primaryInf = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @('PrimaryInfPath')) -Default ''
    if (-not [string]::IsNullOrWhiteSpace($primaryInf)) {
        $names += [System.IO.Path]::GetFileName($primaryInf)
    }
    $sourceInf = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @('SourceInfPath')) -Default ''
    if (-not [string]::IsNullOrWhiteSpace($sourceInf)) {
        $names += [System.IO.Path]::GetFileName($sourceInf)
    }

    $sourceFiles = @($Driver.CaminhosArquivos | Where-Object { $_ })
    if (Get-Command -Name Get-InfNamesFromSourceFiles -ErrorAction SilentlyContinue) {
        $names += @(Get-InfNamesFromSourceFiles -SourceFiles $sourceFiles)
    }
    else {
        $names += @($sourceFiles |
            Where-Object { [System.IO.Path]::GetExtension($_) -ieq '.inf' } |
            ForEach-Object { [System.IO.Path]::GetFileName($_) })
    }

    $display = @($names | Where-Object { $_ } | Select-Object -Unique)
    if ($display.Count -eq 0) {
        return ''
    }
    return ($display -join ', ')
}

function Test-BackupDriverMatchesFilter {
    param(
        [object]$Driver,
        [string]$Filter
    )

    if ([string]::IsNullOrWhiteSpace($Filter)) {
        return $true
    }

    $text = @(
        $Driver.Driver,
        $Driver.Fabricante,
        $Driver.Versao,
        $Driver.Arquitetura,
        $Driver.Status,
        $Driver.PublishedName,
        $Driver.OriginalInfName,
        (Get-BackupDriverInfDisplay -Driver $Driver)
    ) -join ' '

    return ($text -like ('*' + $Filter.Trim() + '*'))
}

function Update-BackupCounters {
    $state = Get-DriverVaultState
    $found = @($state.LastDrivers).Count
    $selected = @($state.LastDrivers | Where-Object { $_.SelectedForBackup }).Count

    if ($state.Ui.ContainsKey('BackupFoundLabel') -and $state.Ui.BackupFoundLabel) {
        $state.Ui.BackupFoundLabel.Text = "Drivers encontrados: $found"
    }
    if ($state.Ui.ContainsKey('BackupSelectedLabel') -and $state.Ui.BackupSelectedLabel) {
        $state.Ui.BackupSelectedLabel.Text = "Drivers selecionados: $selected"
    }
}

function Update-DriverGrid {
    param(
        [object[]]$Drivers
    )

    $state = Get-DriverVaultState
    if (-not ($state.Ui.ContainsKey('Grid') -and $state.Ui.Grid)) {
        return
    }

    if ($PSBoundParameters.ContainsKey('Drivers') -and $null -ne $Drivers) {
        $state.LastDrivers = @($Drivers | Where-Object { $_ })
    }

    $grid = $state.Ui.Grid
    $filter = ''
    if ($state.Ui.ContainsKey('BackupFilterText') -and $state.Ui.BackupFilterText) {
        $filter = $state.Ui.BackupFilterText.Text
    }

    $maxRows = 1000
    if ($state.Contains('RestoreGridMaxRows') -and $state.RestoreGridMaxRows -gt 0) {
        $maxRows = [int]$state.RestoreGridMaxRows
    }

    $grid.SuspendLayout()
    try {
        $grid.Rows.Clear()
        $displayed = 0
        $matched = 0
        foreach ($driver in @($state.LastDrivers | Where-Object { $_ -and (Test-BackupDriverMatchesFilter -Driver $_ -Filter $filter) })) {
            $matched++
            if ($displayed -ge $maxRows) {
                continue
            }

            $rowIndex = $grid.Rows.Add(
                [bool]$driver.SelectedForBackup,
                $driver.Driver,
                $driver.Fabricante,
                $driver.Versao,
                $driver.Arquitetura,
                (Get-BackupDriverInfDisplay -Driver $driver),
                $driver.Status
            )
            $grid.Rows[$rowIndex].Tag = $driver
            $displayed++
            if (($displayed % 100) -eq 0) {
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        if ($state.Ui.ContainsKey('BackupVisibleLabel') -and $state.Ui.BackupVisibleLabel) {
            if ($matched -gt $displayed) {
                $state.Ui.BackupVisibleLabel.Text = "Exibindo: $displayed de $matched filtrados"
            }
            else {
                $state.Ui.BackupVisibleLabel.Text = "Exibindo: $displayed"
            }
        }
    }
    finally {
        $grid.ResumeLayout()
    }

    Update-BackupCounters
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-SelectedBackupDrivers {
    $state = Get-DriverVaultState
    $grid = $state.Ui.Grid
    if (-not $grid) {
        return @()
    }

    if ($grid.IsCurrentCellDirty) {
        $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) | Out-Null
    }

    foreach ($row in $grid.Rows) {
        if ($row.IsNewRow) {
            continue
        }
        $driver = $row.Tag
        if (-not $driver) {
            continue
        }
        $driver.SelectedForBackup = [bool]$row.Cells['Select'].Value
    }

    foreach ($driver in @($state.LastDrivers | Where-Object { $_ })) {
        if (-not $driver.SelectedForBackup -and $driver.BackupStatus -ne 'Success' -and $driver.BackupStatus -ne 'Incomplete' -and $driver.BackupStatus -ne 'Failed') {
            $driver.Status = 'Encontrado'
        }
    }

    $selected = @($state.LastDrivers | Where-Object { $_.SelectedForBackup })
    Update-BackupCounters
    return $selected
}

function Test-RestorableDriverMatchesFilter {
    param(
        [object]$Driver,
        [string]$Filter
    )

    if ([string]::IsNullOrWhiteSpace($Filter)) {
        return $true
    }

    $text = @(
        $Driver.Driver,
        $Driver.Fabricante,
        $Driver.Versao,
        $Driver.Arquitetura,
        $Driver.Status,
        $Driver.InfPath,
        $Driver.DriverFolder
    ) -join ' '

    return ($text -like ('*' + $Filter.Trim() + '*'))
}

function Update-RestoreCounters {
    $state = Get-DriverVaultState
    $found = @($state.LastRestorableDrivers).Count
    $selected = @($state.LastRestorableDrivers | Where-Object { $_.Selected }).Count

    if ($state.Ui.ContainsKey('RestoreFoundLabel') -and $state.Ui.RestoreFoundLabel) {
        $state.Ui.RestoreFoundLabel.Text = "Drivers encontrados: $found"
    }
    if ($state.Ui.ContainsKey('RestoreSelectedLabel') -and $state.Ui.RestoreSelectedLabel) {
        $state.Ui.RestoreSelectedLabel.Text = "Drivers selecionados: $selected"
    }
}

function Update-RestoreGrid {
    $state = Get-DriverVaultState
    if (-not ($state.Ui.ContainsKey('RestoreGrid') -and $state.Ui.RestoreGrid)) {
        return
    }

    $grid = $state.Ui.RestoreGrid
    $filter = ''
    if ($state.Ui.ContainsKey('RestoreFilterText') -and $state.Ui.RestoreFilterText) {
        $filter = $state.Ui.RestoreFilterText.Text
    }

    $maxRows = 1000
    if ($state.Contains('RestoreGridMaxRows') -and $state.RestoreGridMaxRows -gt 0) {
        $maxRows = [int]$state.RestoreGridMaxRows
    }

    $grid.SuspendLayout()
    try {
        $grid.Rows.Clear()
        $displayed = 0
        $matched = 0
        foreach ($driver in @($state.LastRestorableDrivers | Where-Object { $_ -and (Test-RestorableDriverMatchesFilter -Driver $_ -Filter $filter) })) {
            $matched++
            if ($displayed -ge $maxRows) {
                continue
            }

            $backupDisplay = $driver.DriverFolder
            if ([string]::IsNullOrWhiteSpace($backupDisplay)) {
                $backupDisplay = $driver.BackupPath
            }

            $rowIndex = $grid.Rows.Add($driver.Selected, $driver.Driver, $driver.Fabricante, $driver.Versao, $driver.Arquitetura, $driver.Status, $driver.InfPath, $backupDisplay)
            $grid.Rows[$rowIndex].Tag = $driver
            $displayed++
            if (($displayed % 100) -eq 0) {
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        if ($state.Ui.ContainsKey('RestoreVisibleLabel') -and $state.Ui.RestoreVisibleLabel) {
            if ($matched -gt $displayed) {
                $state.Ui.RestoreVisibleLabel.Text = "Exibindo: $displayed de $matched filtrados"
            }
            else {
                $state.Ui.RestoreVisibleLabel.Text = "Exibindo: $displayed"
            }
        }
    }
    finally {
        $grid.ResumeLayout()
    }

    Update-RestoreCounters
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-SelectedRestorableDrivers {
    $state = Get-DriverVaultState
    $grid = $state.Ui.RestoreGrid
    if (-not $grid) {
        return @()
    }

    if ($grid.IsCurrentCellDirty) {
        $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) | Out-Null
    }

    foreach ($row in $grid.Rows) {
        if ($row.IsNewRow) {
            continue
        }
        $driver = $row.Tag
        if (-not $driver) {
            continue
        }
        $isSelected = [bool]$row.Cells['Select'].Value
        $isBroken = ($driver.IsValidated -and (-not $driver.InfExists -or -not $driver.DriverFolderExists -or $driver.MissingFiles.Count -gt 0 -or $driver.Status -eq 'Assinatura invalida'))
        if ($isSelected -and $isBroken) {
            $driver.Selected = $false
            $row.Cells['Select'].Value = $false
            Add-AlertText ("Driver ignorado na selecao por pacote invalido: {0}" -f $driver.Driver)
            continue
        }
        $driver.Selected = $isSelected
    }

    $selected = @($state.LastRestorableDrivers | Where-Object { $_.Selected })
    Update-RestoreCounters
    return $selected
}

function Update-BackupProgress {
    param(
        [int]$Value,
        [int]$Maximum
    )

    $state = Get-DriverVaultState
    if ($state.Ui.ContainsKey('Progress') -and $state.Ui.Progress) {
        $state.Ui.Progress.Minimum = 0
        $state.Ui.Progress.Maximum = [Math]::Max($Maximum, 1)
        $state.Ui.Progress.Value = [Math]::Min($Value, $state.Ui.Progress.Maximum)
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Open-LastReport {
    $state = Get-DriverVaultState
    if ($state.LastReportPath -and (Test-Path -LiteralPath $state.LastReportPath)) {
        Start-Process -FilePath $state.LastReportPath
        return
    }

    [System.Windows.Forms.MessageBox]::Show('Nenhum relatorio DOCX foi gerado nesta sessao ainda.', 'Relatorio indisponivel', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Set-DriverGridTheme {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.DataGridView]$Grid
    )

    $Grid.BackgroundColor = Get-ThemeColor '#111827'
    $Grid.BorderStyle = 'FixedSingle'
    $Grid.EnableHeadersVisualStyles = $false
    $Grid.ColumnHeadersDefaultCellStyle.BackColor = Get-ThemeColor '#1F2937'
    $Grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
    $Grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = Get-ThemeColor '#1F2937'
    $Grid.DefaultCellStyle.BackColor = Get-ThemeColor '#182230'
    $Grid.DefaultCellStyle.ForeColor = Get-ThemeColor '#E5E7EB'
    $Grid.DefaultCellStyle.SelectionBackColor = Get-ThemeColor '#2563EB'
    $Grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $Grid.RowHeadersVisible = $false
    $Grid.AllowUserToAddRows = $false
    $Grid.AllowUserToDeleteRows = $false
    $Grid.ReadOnly = $true
    $Grid.AutoSizeColumnsMode = 'Fill'
}

function Invoke-MaintenanceCleanupFromUi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfirmationMessage,
        [Parameter(Mandatory = $true)]
        [scriptblock]$CleanupAction
    )

    $choice = [System.Windows.Forms.MessageBox]::Show(
        $ConfirmationMessage,
        'Confirmar limpeza',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    try {
        $result = & $CleanupAction
        Add-AlertText $result.Message
        [System.Windows.Forms.MessageBox]::Show(
            $result.Message,
            'Limpeza concluida',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $(if ($result.Success) { [System.Windows.Forms.MessageBoxIcon]::Information } else { [System.Windows.Forms.MessageBoxIcon]::Warning })
        ) | Out-Null
        if (-not $result.Success) {
            foreach ($errorMessage in @($result.Errors)) {
                Add-AlertText $errorMessage
            }
        }
    } catch {
        Add-AlertText ("Erro na limpeza: {0}" -f $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Erro na limpeza',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}
