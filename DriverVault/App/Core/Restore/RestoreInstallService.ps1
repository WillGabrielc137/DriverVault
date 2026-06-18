# Modulo extraido de RestoreService.ps1.



function Invoke-RestoreCallback {
    param(
        [scriptblock]$Callback,
        [object[]]$Arguments
    )

    if (-not $Callback) {
        return
    }
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

function Remove-InstalledPrinterDriverForRestore {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InstalledDriver
    )

    if (-not (Get-Command -Name Remove-PrinterDriver -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Removed = $false; Message = 'Remove-PrinterDriver nao esta disponivel neste sistema.' }
    }

    try {
        Remove-PrinterDriver -Name $InstalledDriver.Driver -ErrorAction Stop
        return [pscustomobject]@{ Removed = $true; Message = 'Driver existente removido.' }
    }
    catch {
        return [pscustomobject]@{ Removed = $false; Message = $_.Exception.Message }
    }
}

function Update-RestorableDriverDiagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver,
        [Parameter(Mandatory = $true)]
        [object]$Diagnostics
    )

    $Driver.InfPath = $Diagnostics.InfFullPath
    $Driver.DriverFolder = $Diagnostics.DriverFolder
    $Driver.InfExists = $Diagnostics.InfExists
    $Driver.DriverFolderExists = $Diagnostics.DriverFolderExists
    $Driver.HasAdditionalFiles = $Diagnostics.HasAdditionalFiles
    $Driver.PackageFileCount = $Diagnostics.PackageFileCount
    $Driver.MissingFiles = @($Diagnostics.MissingFiles)
    $Driver.CatalogFiles = @($Diagnostics.CatalogFiles)
    $Driver.CatalogPath = $Diagnostics.CatalogPath
    $Driver.CatalogSignatureStatus = $Diagnostics.CatalogSignatureStatus
    $Driver.CatalogSignatureStatusMessage = $Diagnostics.CatalogSignatureStatusMessage
    $Driver.CatalogSignatureValid = $Diagnostics.CatalogSignatureValid
    $Driver.CatalogCertificateTrusted = $Diagnostics.CatalogCertificateTrusted
    $Driver.CatalogSignerSubject = $Diagnostics.CatalogSignerSubject
    $Driver.CatalogSignerIssuer = $Diagnostics.CatalogSignerIssuer
    $Driver.CatalogSignerThumbprint = $Diagnostics.CatalogSignerThumbprint
    $Driver.CatalogSignerNotBefore = $Diagnostics.CatalogSignerNotBefore
    $Driver.CatalogSignerNotAfter = $Diagnostics.CatalogSignerNotAfter
    $Driver.IsInstallable = $Diagnostics.IsInstallable
    $Driver.IsValidated = $true
}

function Resolve-RestorableDriverInfForValidation {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver
    )

    if ($Driver.InfPath -and (Test-Path -LiteralPath $Driver.InfPath -PathType Leaf)) {
        $Driver.InfPath = (Resolve-Path -LiteralPath $Driver.InfPath).Path
        if (-not $Driver.DriverFolder -or -not (Test-Path -LiteralPath $Driver.DriverFolder -PathType Container)) {
            $Driver.DriverFolder = Split-Path -Parent $Driver.InfPath
        }
        return
    }

    if ($Driver.DriverFolder -and (Test-Path -LiteralPath $Driver.DriverFolder -PathType Container) -and $Driver.InfFile) {
        $candidate = Join-Path $Driver.DriverFolder $Driver.InfFile
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $Driver.InfPath = (Resolve-Path -LiteralPath $candidate).Path
            return
        }
    }

    if ($Driver.BackupPath -and $Driver.InfFile) {
        $foundInf = Find-InfInBackup -BackupPath $Driver.BackupPath -InfFile $Driver.InfFile
        if ($foundInf) {
            $Driver.InfPath = $foundInf
            $Driver.DriverFolder = Split-Path -Parent $foundInf
            return
        }
    }

    if ($Driver.DriverFolder -and (Test-Path -LiteralPath $Driver.DriverFolder -PathType Container)) {
        $firstInf = Get-ChildItem -LiteralPath $Driver.DriverFolder -Filter *.inf -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($firstInf) {
            $Driver.InfPath = $firstInf.FullName
            $Driver.InfFile = $firstInf.Name
            return
        }
    }
}

function Ensure-RestorableDriverCertificateFile {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver
    )

    if ($Driver.CatalogCertificatePath -and (Test-Path -LiteralPath $Driver.CatalogCertificatePath -PathType Leaf)) {
        return $Driver.CatalogCertificatePath
    }
    if (-not $Driver.CatalogPath -or -not (Test-Path -LiteralPath $Driver.CatalogPath -PathType Leaf)) {
        return ''
    }

    $certExport = Export-DriverCatalogCertificate -CatalogPath $Driver.CatalogPath -DestinationFolder (Join-Path $Driver.BackupPath 'Certificates')
    if ($certExport.Exported) {
        $Driver.CatalogCertificatePath = $certExport.CertificatePath
        try {
            $Driver.CatalogCertificateRelativePath = Get-RelativePathFromBase -BasePath $Driver.BackupPath -TargetPath $certExport.CertificatePath
        }
        catch {
            $Driver.CatalogCertificateRelativePath = ''
        }
        return $certExport.CertificatePath
    }

    return ''
}

function Install-DriverFromBackupInf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InfPath,
        [string]$DriverName = '',
        [switch]$AllowUntrustedSignedCatalog
    )

    $diagnostics = Get-RestorablePackageDiagnostics -InfPath $InfPath -DriverFolder (Split-Path -Parent $InfPath)
    if (-not $diagnostics.InfExists) {
        throw (New-RestoreInfErrorMessage -DriverName $DriverName -Diagnostics $diagnostics -PnPUtilResult $null)
    }
    if ($diagnostics.MissingFiles.Count -gt 0) {
        throw (New-RestoreInfErrorMessage -DriverName $DriverName -Diagnostics $diagnostics -PnPUtilResult $null)
    }
    if (-not $diagnostics.HasAdditionalFiles) {
        throw (New-RestoreInfErrorMessage -DriverName $DriverName -Diagnostics $diagnostics -PnPUtilResult $null)
    }
    if ($diagnostics.CatalogFiles.Count -gt 0 -and -not $diagnostics.CatalogSignatureValid) {
        $canContinue = ($AllowUntrustedSignedCatalog -and (Test-DriverSignatureCanPromptForTrust -SignatureInfo $diagnostics.CatalogSignature))
        if (-not $canContinue) {
            throw (New-RestoreInfErrorMessage -DriverName $DriverName -Diagnostics $diagnostics -PnPUtilResult $null)
        }
    }

    $infFullPath = $diagnostics.InfFullPath
    $driverFolder = $diagnostics.DriverFolder

    $pnputil = Join-Path $env:windir 'System32\pnputil.exe'
    if (-not (Test-Path -LiteralPath $pnputil -PathType Leaf)) {
        $pnputil = 'pnputil.exe'
    }

    return Invoke-ProcessWithTimeout -FileName $pnputil -Arguments @('/add-driver', $infFullPath, '/install') -WorkingDirectory $driverFolder -TimeoutSeconds 180
}

function New-RestoreInfErrorMessage {
    param(
        [string]$DriverName,
        [Parameter(Mandatory = $true)]
        [object]$Diagnostics,
        [object]$PnPUtilResult
    )

    $lines = New-Object System.Collections.Generic.List[string]
    if ($DriverName) {
        $lines.Add("Falha ao instalar $DriverName.")
    }
    else {
        $lines.Add('Falha ao instalar driver.')
    }
    $lines.Add(("INF usado: {0}" -f $Diagnostics.InfFullPath))
    $lines.Add(("Pasta do driver: {0}" -f $Diagnostics.DriverFolder))
    $lines.Add(("Arquivo INF existe: {0}" -f ($(if ($Diagnostics.InfExists) { 'Sim' } else { 'Nao' }))))
    $lines.Add(("Pasta do driver existe: {0}" -f ($(if ($Diagnostics.DriverFolderExists) { 'Sim' } else { 'Nao' }))))
    $lines.Add(("Arquivos adicionais no pacote: {0}" -f ($(if ($Diagnostics.HasAdditionalFiles) { 'Sim' } else { 'Nao' }))))
    $lines.Add(("Total de arquivos na pasta: {0}" -f $Diagnostics.PackageFileCount))
    if ($Diagnostics.CatalogPath) {
        $lines.Add(("Catalogo usado: {0}" -f $Diagnostics.CatalogPath))
        $lines.Add(("Assinatura do catalogo: {0}" -f $Diagnostics.CatalogSignatureStatus))
        if ($Diagnostics.CatalogSignatureStatusMessage) {
            $lines.Add(("Mensagem da assinatura: {0}" -f $Diagnostics.CatalogSignatureStatusMessage))
        }
        if ($Diagnostics.CatalogSignerThumbprint) {
            $lines.Add(("Certificado: {0}" -f $Diagnostics.CatalogSignerThumbprint))
            $lines.Add(("Emissor: {0}" -f $Diagnostics.CatalogSignerIssuer))
            $lines.Add(("Validade: {0} ate {1}" -f $Diagnostics.CatalogSignerNotBefore, $Diagnostics.CatalogSignerNotAfter))
        }
    }
    if (-not $Diagnostics.HasAdditionalFiles) {
        $lines.Add('Pacote incompleto: a pasta contem apenas o INF ou nao possui arquivos auxiliares suficientes.')
    }
    if ($Diagnostics.MissingFiles.Count -gt 0) {
        $lines.Add(("Arquivos referenciados ausentes: {0}" -f ($Diagnostics.MissingFiles -join ', ')))
        $catalogMissing = @($Diagnostics.MissingFiles | Where-Object { [System.IO.Path]::GetExtension($_) -ieq '.cat' })
        if ($catalogMissing.Count -gt 0) {
            $lines.Add('O arquivo de catalogo de assinatura do driver esta ausente.')
            $lines.Add('Esse arquivo e obrigatorio para instalar o pacote pelo Windows.')
            $lines.Add('Provavel causa: backup incompleto ou copia feita da pasta errada.')
        }
        $lines.Add('Sugestao: refaca o backup apos a correcao da rotina de exportacao do pacote.')
    }
    if ($Diagnostics.CatalogFiles.Count -gt 0 -and -not $Diagnostics.CatalogSignatureValid) {
        if ($Diagnostics.CatalogSignerThumbprint) {
            $lines.Add('O pacote do driver possui catalogo de assinatura, mas o certificado/assinatura nao e confiavel nesta maquina.')
        }
        else {
            $lines.Add('O catalogo do driver nao possui assinatura valida. A instalacao nao sera forcada.')
        }
    }
    if ($PnPUtilResult) {
        $lines.Add(("Codigo de saida do pnputil: {0}" -f $PnPUtilResult.ExitCode))
        if ($PnPUtilResult.Output) {
            $lines.Add(("Saida do pnputil: {0}" -f (($PnPUtilResult.Output -replace '\r?\n', ' ').Trim())))
        }
        if ($PnPUtilResult.Error) {
            $lines.Add(("Erro do pnputil: {0}" -f (($PnPUtilResult.Error -replace '\r?\n', ' ').Trim())))
        }
    }
    return ($lines -join [Environment]::NewLine)
}

function Get-RestoreDriversSelectedForProcessing {
    param(
        [object[]]$Drivers
    )

    return @($Drivers | Where-Object { $_ -and $_.Selected })
}

function Start-DriverRestoreJob {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Drivers,
        [scriptblock]$StatusCallback,
        [scriptblock]$AlertCallback,
        [scriptblock]$GridCallback,
        [scriptblock]$DecisionCallback,
        [scriptblock]$CertificateDecisionCallback
    )

    $receivedDrivers = @($Drivers | Where-Object { $_ })
    $notSelectedDrivers = @($receivedDrivers | Where-Object { -not $_.Selected })
    $Drivers = @(Get-RestoreDriversSelectedForProcessing -Drivers $receivedDrivers)

    if (@($Drivers).Count -eq 0) {
        throw 'Nenhum driver foi selecionado para instalacao.'
    }

    if (-not (Test-DriverVaultAdministrator)) {
        throw 'A instalacao/restauracao de drivers precisa ser executada como administrador.'
    }

    Write-DriverVaultLog 'Inicio da restauracao/instalacao de drivers.'
    Write-DriverVaultLog ("Total de drivers recebidos pelo job de restauracao: {0}" -f $receivedDrivers.Count)
    Write-DriverVaultLog ("Drivers ignorados por nao estarem selecionados: {0}" -f $notSelectedDrivers.Count)
    Write-DriverVaultLog ("Total de drivers selecionados para restauracao: {0}" -f @($Drivers).Count)
    foreach ($selectedDriver in @($Drivers)) {
        Write-DriverVaultLog ("Selecionado para restauracao: {0} | Versao: {1} | INF provavel: {2}" -f $selectedDriver.Driver, $selectedDriver.Versao, $selectedDriver.InfPath)
    }
    Invoke-RestoreCallback $StatusCallback @('Coletando drivers ja instalados nesta maquina...')
    $installedDrivers = @(Get-InstalledPrinterDriversForRestore)
    $total = @($Drivers).Count
    $index = 0

    foreach ($driver in @($Drivers)) {
        $index++
        Invoke-RestoreCallback $StatusCallback @(("Validando driver selecionado {0} de {1}: {2}" -f $index, $total, $driver.Driver))
        Write-DriverVaultLog ("Etapa 3 - validando driver selecionado: {0} | INF provavel: {1}" -f $driver.Driver, $driver.InfPath)

        Resolve-RestorableDriverInfForValidation -Driver $driver
        Repair-MissingCatalogFilesFromBackup -InfPath $driver.InfPath -DriverFolder $driver.DriverFolder -BackupPath $driver.BackupPath
        $diagnostics = Get-RestorablePackageDiagnostics -InfPath $driver.InfPath -DriverFolder $driver.DriverFolder
        Update-RestorableDriverDiagnostics -Driver $driver -Diagnostics $diagnostics
        Write-DriverVaultLog ("Validacao concluida para {0}: InfExiste={1}; PastaExiste={2}; Arquivos={3}; Ausentes={4}; Catalogos={5}; AssinaturaValida={6}" -f $driver.Driver, $diagnostics.InfExists, $diagnostics.DriverFolderExists, $diagnostics.PackageFileCount, @($diagnostics.MissingFiles).Count, @($diagnostics.CatalogFiles).Count, $diagnostics.CatalogSignatureValid)

        if (-not $diagnostics.InfExists) {
            $driver.Status = 'Sem INF'
            $driver.Erros = New-RestoreInfErrorMessage -DriverName $driver.Driver -Diagnostics $diagnostics -PnPUtilResult $null
            Write-DriverVaultLog ("Falha na restauracao de {0}: {1}" -f $driver.Driver, ($driver.Erros -replace '\r?\n', ' ')) 'ERROR'
            Invoke-RestoreCallback $AlertCallback @($driver.Erros)
            Invoke-RestoreCallback $GridCallback @()
            continue
        }

        if ($diagnostics.MissingFiles.Count -gt 0) {
            $driver.Status = 'Pacote incompleto'
            $driver.Erros = New-RestoreInfErrorMessage -DriverName $driver.Driver -Diagnostics $diagnostics -PnPUtilResult $null
            Write-DriverVaultLog ("Falha na restauracao de {0}: {1}" -f $driver.Driver, ($driver.Erros -replace '\r?\n', ' ')) 'ERROR'
            Invoke-RestoreCallback $AlertCallback @($driver.Erros)
            Invoke-RestoreCallback $GridCallback @()
            continue
        }

        if (-not $diagnostics.HasAdditionalFiles) {
            $driver.Status = 'Pacote incompleto'
            $driver.Erros = New-RestoreInfErrorMessage -DriverName $driver.Driver -Diagnostics $diagnostics -PnPUtilResult $null
            Write-DriverVaultLog ("Falha na restauracao de {0}: {1}" -f $driver.Driver, ($driver.Erros -replace '\r?\n', ' ')) 'ERROR'
            Invoke-RestoreCallback $AlertCallback @($driver.Erros)
            Invoke-RestoreCallback $GridCallback @()
            continue
        }

        $allowUntrustedCatalog = $false
        if ($diagnostics.CatalogFiles.Count -gt 0 -and -not $diagnostics.CatalogSignatureValid) {
            if (Test-DriverSignatureCanPromptForTrust -SignatureInfo $diagnostics.CatalogSignature) {
                $certificatePath = Ensure-RestorableDriverCertificateFile -Driver $driver
                $choice = 'Cancel'
                if ($CertificateDecisionCallback) {
                    $choice = & $CertificateDecisionCallback $driver $diagnostics $certificatePath
                }

                if ($choice -eq 'Cancel') {
                    $driver.Status = 'Cancelado'
                    Write-DriverVaultLog ("Restauracao cancelada pelo usuario durante decisao de certificado: {0}" -f $driver.Driver) 'WARN'
                    Invoke-RestoreCallback $AlertCallback @('Restauracao cancelada pelo usuario por certificado nao confiavel.')
                    Invoke-RestoreCallback $GridCallback @()
                    break
                }

                if ($choice -eq 'Import') {
                    try {
                        if ([string]::IsNullOrWhiteSpace($certificatePath)) {
                            throw 'Nao foi possivel exportar o certificado a partir do catalogo do driver.'
                        }
                        $importResult = Import-DriverCatalogCertificate -CertificatePath $certificatePath
                        Write-DriverVaultLog ("Certificado importado para driver {0}: {1}" -f $driver.Driver, $importResult.Thumbprint)
                        Invoke-RestoreCallback $AlertCallback @(("Certificado importado para TrustedPublisher: {0}" -f $importResult.Thumbprint))
                        $diagnostics = Get-RestorablePackageDiagnostics -InfPath $driver.InfPath -DriverFolder $driver.DriverFolder
                        Update-RestorableDriverDiagnostics -Driver $driver -Diagnostics $diagnostics
                        if (-not $diagnostics.CatalogSignatureValid) {
                            $driver.Status = 'Certificado nao confiavel'
                            $driver.Erros = New-RestoreInfErrorMessage -DriverName $driver.Driver -Diagnostics $diagnostics -PnPUtilResult $null
                            Write-DriverVaultLog ("Falha na restauracao de {0}: certificado continua nao confiavel." -f $driver.Driver) 'ERROR'
                            Invoke-RestoreCallback $AlertCallback @($driver.Erros)
                            Invoke-RestoreCallback $GridCallback @()
                            continue
                        }
                    }
                    catch {
                        $driver.Status = 'Falha certificado'
                        $driver.Erros = $_.Exception.Message
                        Write-DriverVaultLog ("Falha de certificado para {0}: {1}" -f $driver.Driver, $driver.Erros) 'ERROR'
                        Invoke-RestoreCallback $AlertCallback @($driver.Erros)
                        Invoke-RestoreCallback $GridCallback @()
                        continue
                    }
                }
                elseif ($choice -eq 'Continue') {
                    $allowUntrustedCatalog = $true
                    Invoke-RestoreCallback $AlertCallback @(("Usuario optou por continuar sem importar certificado: {0}" -f $driver.Driver))
                }
            }
            else {
                $driver.Status = 'Assinatura invalida'
                $driver.Erros = New-RestoreInfErrorMessage -DriverName $driver.Driver -Diagnostics $diagnostics -PnPUtilResult $null
                Write-DriverVaultLog ("Falha na restauracao de {0}: assinatura invalida." -f $driver.Driver) 'ERROR'
                Invoke-RestoreCallback $AlertCallback @($driver.Erros)
                Invoke-RestoreCallback $GridCallback @()
                continue
            }
        }

        Invoke-RestoreCallback $StatusCallback @(("Verificando duplicidade do selecionado {0} de {1}: {2}" -f $index, $total, $driver.Driver))
        $match = Find-InstalledDriverMatch -BackupDriver $driver -InstalledDrivers $installedDrivers
        if ($match) {
            $choice = 'Skip'
            if ($DecisionCallback) {
                $choice = & $DecisionCallback $driver $match
            }

            if ($choice -eq 'Cancel') {
                $driver.Status = 'Cancelado'
                Write-DriverVaultLog ("Restauracao cancelada pelo usuario em conflito de duplicidade: {0}" -f $driver.Driver) 'WARN'
                Invoke-RestoreCallback $AlertCallback @('Restauracao cancelada pelo usuario.')
                Invoke-RestoreCallback $GridCallback @()
                break
            }

            if ($choice -eq 'Skip') {
                $driver.Status = 'Ignorado'
                $driver.Avisos = 'Driver existente mantido pelo usuario.'
                Write-DriverVaultLog ("Driver selecionado ignorado porque ja existe e o usuario manteve o existente: {0}" -f $driver.Driver) 'WARN'
                Invoke-RestoreCallback $AlertCallback @(("Driver ignorado porque ja existe: {0}" -f $driver.Driver))
                Invoke-RestoreCallback $GridCallback @()
                continue
            }

            if ($choice -eq 'Replace') {
                $removeResult = Remove-InstalledPrinterDriverForRestore -InstalledDriver $match
                if ($removeResult.Removed) {
                    Write-DriverVaultLog ("Driver existente removido antes da substituicao: {0}" -f $match.Driver)
                    Invoke-RestoreCallback $AlertCallback @(("Driver existente removido: {0}" -f $match.Driver))
                    $installedDrivers = @($installedDrivers | Where-Object { $_.Driver -ne $match.Driver })
                }
                else {
                    Write-DriverVaultLog ("Nao foi possivel remover driver existente {0}: {1}" -f $match.Driver, $removeResult.Message) 'WARN'
                    Invoke-RestoreCallback $AlertCallback @(("Nao foi possivel remover o driver existente. O Windows tentara adicionar/atualizar o pacote: {0}" -f $removeResult.Message))
                }
            }
        }

        try {
            Invoke-RestoreCallback $StatusCallback @(("Instalando driver selecionado {0} de {1}: {2}" -f $index, $total, $driver.Driver))
            Write-DriverVaultLog ("Etapa 5 - chamando pnputil somente para driver selecionado: {0} | INF: {1}" -f $driver.Driver, $driver.InfPath)
            $result = Install-DriverFromBackupInf -InfPath $driver.InfPath -DriverName $driver.Driver -AllowUntrustedSignedCatalog:$allowUntrustedCatalog
            if ($result.ExitCode -eq 0) {
                $driver.Status = 'Instalado'
                $driver.Avisos = ($result.Output -replace '\r?\n', ' ').Trim()
                Write-DriverVaultLog ("Driver instalado com sucesso: {0}" -f $driver.Driver)
                Invoke-RestoreCallback $AlertCallback @(("Driver instalado: {0}" -f $driver.Driver))
            }
            else {
                $driver.Status = 'Falha'
                $driver.Erros = New-RestoreInfErrorMessage -DriverName $driver.Driver -Diagnostics $diagnostics -PnPUtilResult $result
                Write-DriverVaultLog ("Falha ao instalar {0}: {1}" -f $driver.Driver, ($driver.Erros -replace '\r?\n', ' ')) 'ERROR'
                Invoke-RestoreCallback $AlertCallback @($driver.Erros)
            }
        }
        catch {
            $driver.Status = 'Falha'
            $driver.Erros = $_.Exception.Message
            Write-DriverVaultLog ("Falha ao instalar {0}: {1}" -f $driver.Driver, $driver.Erros) 'ERROR'
            Invoke-RestoreCallback $AlertCallback @($driver.Erros)
        }

        Invoke-RestoreCallback $GridCallback @()
    }

    Write-DriverVaultLog 'Fim da restauracao/instalacao de drivers.'
    Invoke-RestoreCallback $StatusCallback @('Restauracao finalizada.')
}
