# Modulo extraido de BackupService.ps1.



function Invoke-BackupCallback {
    param(
        [scriptblock]$Callback,
        [object[]]$Arguments
    )

    if ($Callback) {
        if ($Arguments.Count -eq 0) {
            & $Callback
        }
        elseif ($Arguments.Count -eq 1) {
            & $Callback $Arguments[0]
        }
        else {
            & $Callback @Arguments
        }
    }
}

function Start-DriverVaultJob {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [object[]]$Drivers = @(),
        [object[]]$AllDriversForManifest = @(),
        [scriptblock]$StatusCallback,
        [scriptblock]$AlertCallback,
        [scriptblock]$GridCallback,
        [scriptblock]$ProgressCallback,
        [scriptblock]$DuplicateDecisionCallback,
        [switch]$SkipDocxReport
    )

    $stage = 'iniciando backup'
    try {
        $stage = 'validando selecao de drivers'
        $drivers = @($Drivers | Where-Object { $_ })
        if ($drivers.Count -eq 0) {
            throw 'Nenhum driver selecionado para backup. Liste os drivers e marque pelo menos um item antes de iniciar.'
        }

        $stage = 'criando pasta de backup'
        if (-not (Test-Path -LiteralPath $DestinationRoot)) {
            New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
        }

        $state = Get-DriverVaultState
        $backupPath = New-DriverVaultFolder -BackupPath $BackupPath
        $driversRoot = Join-Path $backupPath 'Drivers'
        $state.LastBackupPath = $backupPath
        $state.LastReportPath = $null

        Start-DriverVaultLog -BackupPath $backupPath
        Invoke-BackupCallback $StatusCallback @('Preparando drivers selecionados para backup...')
        Invoke-BackupCallback $AlertCallback @("Backup iniciado em: $backupPath")

        $stage = 'validando selecao de drivers'
        $manifestDrivers = @($AllDriversForManifest | Where-Object { $_ })
        if ($manifestDrivers.Count -eq 0) {
            $manifestDrivers = $drivers
        }

        foreach ($driver in $manifestDrivers) {
            if ($drivers -contains $driver) {
                $driver.SelectedForBackup = $true
                $driver.BackupStatus = 'Pending'
                $driver.IsInstallable = $false
                $driver.ValidationMessages = @()
                $driver.Status = 'Selecionado'
            }
            else {
                $driver.SelectedForBackup = $false
                $driver.BackupStatus = 'Ignored'
                $driver.IsInstallable = $false
                $driver.ValidationMessages = @('Ignorado pelo usuario. Nenhum arquivo foi copiado para este driver.')
                $driver.Status = 'Ignorado pelo usuario'
            }
        }

        $state.LastDrivers = $manifestDrivers

        $stage = 'atualizando interface apos coleta'
        Invoke-BackupCallback $GridCallback @(, $manifestDrivers)

        $stage = 'lendo backups existentes para comparacao'
        $existingRepositoryDrivers = @(Get-ExistingRepositoryRecords -RepositoryRoot $DestinationRoot | Where-Object {
                $_.CaminhoBackup -notlike "$backupPath*"
            })

        $processedDrivers = @()
        $duplicateReport = @()
        $errors = @()
        $total = [Math]::Max($drivers.Count, 1)
        $index = 0
        Invoke-BackupCallback $ProgressCallback @(0, $total)

        foreach ($driver in $drivers) {
            $stage = "copiando arquivos do driver $($driver.Driver)"
            $index++
            Invoke-BackupCallback $StatusCallback @(("Fazendo backup do driver {0} de {1}: {2}" -f $index, $drivers.Count, $driver.Driver))
            $driver.Status = 'Processando'

            $compareAgainst = @($processedDrivers + $existingRepositoryDrivers)
            $dups = @(Find-DuplicatesForDriver -Driver $driver -ExistingDrivers $compareAgainst)
            $saveSeparate = $false

            if ($dups.Count -gt 0) {
                $duplicateReport += $dups
                $firstDup = $dups[0]
                $alert = "ATENCAO: Driver possivelmente repetido encontrado. Driver: {0}; Versao existente: {1}; Nova versao encontrada: {2}; Motivo: {3}" -f $driver.Driver, $firstDup.VersaoReferencia, $driver.Versao, $firstDup.Motivo
                Invoke-BackupCallback $AlertCallback @($alert)
                Write-DriverVaultLog $alert 'WARN'

                $choice = 'Keep'
                if ($DuplicateDecisionCallback) {
                    $choice = & $DuplicateDecisionCallback $driver $firstDup
                }

                if ($choice -eq 'Skip') {
                    $driver.Status = 'Ignorado duplicado'
                    $driver.BackupStatus = 'Ignored'
                    $driver.IsInstallable = $false
                    $driver.ValidationMessages = @('Ignorado pelo usuario apos alerta de duplicidade.')
                    $driver.Avisos = 'Usuario optou por ignorar a nova copia apos alerta de duplicidade.'
                    Write-DriverVaultLog ("Driver ignorado por duplicidade: {0}" -f $driver.Driver) 'WARN'
                    $processedDrivers += $driver
                    Invoke-BackupCallback $GridCallback @(, $manifestDrivers)
                    Invoke-BackupCallback $ProgressCallback @([Math]::Min($index, $total), $total)
                    continue
                }
                elseif ($choice -eq 'Separate') {
                    $saveSeparate = $true
                    $driver.Avisos = 'Salvo em pasta separada por decisao do usuario apos alerta de duplicidade.'
                }
                else {
                    $driver.Avisos = 'Mantido junto ao backup apos alerta de duplicidade.'
                }
            }

            $copyResult = Copy-DriverFiles -Driver $driver -DriversRoot $driversRoot -SalvarSeparado:$saveSeparate
            $errors += @($copyResult.Errors)
            $processedDrivers += $driver
            if ($driver.BackupStatus -eq 'Success') {
                Invoke-BackupCallback $AlertCallback @(("Backup concluido: {0}" -f $driver.Driver))
            }
            elseif ($driver.BackupStatus -eq 'Incomplete') {
                Invoke-BackupCallback $AlertCallback @(("Backup incompleto: {0}" -f $driver.Driver))
                foreach ($message in @($driver.ValidationMessages)) {
                    Invoke-BackupCallback $AlertCallback @(" - $message")
                }
            }
            elseif ($driver.BackupStatus -eq 'Failed') {
                Invoke-BackupCallback $AlertCallback @(("Falhou: {0} - {1}" -f $driver.Driver, $driver.Erros))
            }

            $stage = 'atualizando interface durante copia'
            Invoke-BackupCallback $GridCallback @(, $manifestDrivers)
            Invoke-BackupCallback $ProgressCallback @([Math]::Min($index, $total), $total)
        }

        $stage = 'verificando duplicidades finais'
        $currentDuplicates = @(Find-DriverDuplicates -Drivers $drivers)
        $allDuplicates = @($duplicateReport + $currentDuplicates)
        $state.LastDuplicates = @(Find-DriverDuplicates -Drivers @($drivers + $existingRepositoryDrivers))
        if ($state.LastDuplicates.Count -lt $allDuplicates.Count) {
            $state.LastDuplicates = $allDuplicates
        }

        if ($state.LastDuplicates.Count -gt 0) {
            Invoke-BackupCallback $AlertCallback @(("Total de possiveis duplicidades registradas: {0}" -f $state.LastDuplicates.Count))
            foreach ($dup in $state.LastDuplicates) {
                Write-DriverVaultLog ("Duplicidade: {0} ({1}) x {2} ({3}) | {4}" -f $dup.DriverReferencia, $dup.VersaoReferencia, $dup.NovoDriver, $dup.NovaVersao, $dup.Motivo) 'WARN'
            }
        }
        else {
            Invoke-BackupCallback $AlertCallback @('Nenhuma duplicidade encontrada pelos criterios atuais.')
        }

        $stage = 'gerando manifesto'
        New-DriverVaultManifest -Drivers $manifestDrivers -BackupPath $backupPath | Out-Null

        $reportPath = $null
        if ($SkipDocxReport) {
            Invoke-BackupCallback $AlertCallback @('Geracao de relatorio DOCX ignorada nesta execucao.')
        }
        else {
            $stage = 'gerando relatorio'
            $reportPath = New-DriverVaultReport -Drivers $drivers -Duplicados $state.LastDuplicates -BackupPath $backupPath
            $state.LastReportPath = $reportPath
            Invoke-BackupCallback $AlertCallback @("Relatorio gerado em: $reportPath")
        }

        $stage = 'finalizando backup'
        Write-DriverVaultLog 'Fim da execucao.'
        $successCount = @($drivers | Where-Object { $_.BackupStatus -eq 'Success' }).Count
        $incompleteCount = @($drivers | Where-Object { $_.BackupStatus -eq 'Incomplete' }).Count
        $failedCount = @($drivers | Where-Object { $_.BackupStatus -eq 'Failed' }).Count
        $ignoredCount = @($manifestDrivers | Where-Object { $_.BackupStatus -eq 'Ignored' }).Count

        if (($incompleteCount + $failedCount) -gt 0) {
            Invoke-BackupCallback $StatusCallback @(("Backup finalizado com pendencias: {0} concluido(s), {1} incompleto(s), {2} falha(s)." -f $successCount, $incompleteCount, $failedCount))
            Invoke-BackupCallback $AlertCallback @(("Backup finalizado com pendencias. Concluidos: {0}; incompletos: {1}; falhas: {2}; ignorados: {3}" -f $successCount, $incompleteCount, $failedCount, $ignoredCount))
        }
        else {
            Invoke-BackupCallback $StatusCallback @(("Backup concluido: {0}" -f $backupPath))
            Invoke-BackupCallback $AlertCallback @(("Backup concluido. Drivers processados: {0}; ignorados: {1}" -f $successCount, $ignoredCount))
        }
        Invoke-BackupCallback $GridCallback @(, $manifestDrivers)

        return New-BackupResult -BackupPath $backupPath -Drivers $manifestDrivers -Duplicados $state.LastDuplicates -ReportPath $reportPath -Errors $errors
    }
    catch {
        $message = "Falha na etapa '{0}': {1}" -f $stage, $_.Exception.Message
        Write-DriverVaultLog $message 'ERROR'
        throw $message
    }
}
