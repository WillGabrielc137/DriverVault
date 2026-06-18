# Modulo extraido de RestoreService.ps1.



function New-DriverVaultManifest {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Drivers,
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    $manifestPath = Join-Path $BackupPath 'drivers-manifest.json'
    $createdAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $items = @()

    foreach ($driver in @($Drivers | Where-Object { $_ })) {
        $driverFolder = $driver.CaminhoBackup
        $infFiles = @()
        if ($driverFolder -and (Test-Path -LiteralPath $driverFolder)) {
            $infFiles = @(Get-ChildItem -LiteralPath $driverFolder -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue)
        }

        $primaryInf = $null
        $primaryInfPath = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('PrimaryInfPath')) -Default ''
        if ($primaryInfPath -and (Test-Path -LiteralPath $primaryInfPath -PathType Leaf)) {
            $primaryInf = Get-Item -LiteralPath $primaryInfPath
        }
        elseif ($driverFolder -and (Test-Path -LiteralPath $driverFolder -PathType Container)) {
            $primaryInf = Find-PreferredInfFileInFolder -Folder $driverFolder -Driver $driver
        }
        elseif ($infFiles.Count -gt 0) {
            $primaryInf = $infFiles[0]
        }

        $relativeInf = ''
        $infFile = ''
        if ($primaryInf) {
            $relativeInf = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $primaryInf.FullName
            $infFile = [System.IO.Path]::GetFileName($primaryInf.FullName)
        }

        $relativeFolder = ''
        $installerPath = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('InstallerPath')) -Default ''
        $relativeInstaller = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('RelativeInstallerPath')) -Default ''
        if ([string]::IsNullOrWhiteSpace($relativeInstaller) -and $installerPath -and (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
            $relativeInstaller = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $installerPath
        }
        $packageFileCount = 0
        $hasAdditionalFiles = $false
        $missingFiles = @()
        $catalogFiles = @()
        $relativeCatalog = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('RelativeCatalogPath')) -Default ''
        $catalogPath = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('CatalogPath')) -Default ''
        $signatureInfo = $null
        if ($driverFolder -and (Test-Path -LiteralPath $driverFolder)) {
            $relativeFolder = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $driverFolder
            $packageFiles = @(Get-ChildItem -LiteralPath $driverFolder -Recurse -File -ErrorAction SilentlyContinue)
            $packageFileCount = $packageFiles.Count
            if ($primaryInf) {
                $hasAdditionalFiles = ($packageFiles | Where-Object { $_.FullName -ne $primaryInf.FullName } | Select-Object -First 1) -ne $null
                $catalogFiles = @(Get-InfCatalogFiles -InfPath $primaryInf.FullName)
                foreach ($catalog in $catalogFiles) {
                    $catalogPath = Join-Path (Split-Path -Parent $primaryInf.FullName) $catalog
                    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
                        $foundCatalog = Get-ChildItem -LiteralPath $driverFolder -Recurse -File -Filter $catalog -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($foundCatalog) {
                            $catalogPath = $foundCatalog.FullName
                        }
                    }

                    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
                        $missingFiles += $catalog
                    }
                    elseif ([string]::IsNullOrWhiteSpace($relativeCatalog)) {
                        $catalogPath = (Resolve-Path -LiteralPath $catalogPath).Path
                        $relativeCatalog = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $catalogPath
                    }
                }
            }
        }

        if ($catalogPath -and (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
            $signatureInfo = Get-DriverCatalogSignatureInfo -CatalogPath $catalogPath
        }

        $selectedValue = Get-ObjectPropertyValue -Object $driver -Names @('SelectedForBackup')
        $selectedForBackup = if ($null -ne $selectedValue) { [bool]$selectedValue } else { $true }
        $isInstallableValue = Get-ObjectPropertyValue -Object $driver -Names @('IsInstallable')
        $isInstallable = if ($null -ne $isInstallableValue) { [bool]$isInstallableValue } else { ($primaryInf -and $missingFiles.Count -eq 0 -and $packageFileCount -gt 1) }
        $backupStatus = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('BackupStatus')) -Default ''
        if ([string]::IsNullOrWhiteSpace($backupStatus) -or $backupStatus -eq 'N/D' -or $backupStatus -eq 'Pending' -or $backupStatus -eq 'NotStarted') {
            if (-not $selectedForBackup) {
                $backupStatus = 'Ignored'
            }
            elseif ($isInstallable) {
                $backupStatus = 'Success'
            }
            elseif ($driver.Status -match 'incompleto|Pacote incompleto') {
                $backupStatus = 'Incomplete'
            }
            elseif ($driver.Status -match 'Erro|Falhou') {
                $backupStatus = 'Failed'
            }
            else {
                $backupStatus = 'Incomplete'
            }
        }

        $validationMessages = @()
        if ($driver.PSObject.Properties['ValidationMessages']) {
            $validationMessages += @($driver.ValidationMessages | Where-Object { $_ })
        }
        if (-not $selectedForBackup -and $validationMessages.Count -eq 0) {
            $validationMessages += 'Ignorado pelo usuario. Nenhum arquivo foi copiado para este driver.'
        }
        if ($selectedForBackup -and -not $primaryInf -and [string]::IsNullOrWhiteSpace($relativeInstaller)) {
            $validationMessages += 'Nenhum arquivo .inf foi encontrado no pacote exportado.'
            $validationMessages += 'O driver nao podera ser restaurado em outro servidor.'
        }
        if ($missingFiles.Count -gt 0) {
            $validationMessages += ('Catalogo(s) referenciado(s) pelo INF nao encontrado(s): {0}' -f (($missingFiles | Select-Object -Unique) -join ', '))
        }
        $validationMessages = @($validationMessages | Where-Object { $_ } | Select-Object -Unique)

        $items += [pscustomobject]@{
            DriverName                     = $driver.Driver
            SelectedForBackup              = $selectedForBackup
            BackupStatus                   = $backupStatus
            IsInstallable                  = [bool]$isInstallable
            Version                        = $driver.Versao
            Manufacturer                   = $driver.Fabricante
            Architecture                   = $driver.Arquitetura
            OriginalInfName                = $driver.OriginalInfName
            PublishedName                  = $driver.PublishedName
            Provider                       = $driver.DriverPackageProvider
            Class                          = $driver.DriverPackageClass
            DriverPackageVersion           = $driver.DriverPackageVersion
            CatalogFile                    = if ($catalogFiles.Count -gt 0) { $catalogFiles[0] } else { '' }
            CatalogFiles                   = @($catalogFiles)
            RelativeCatalogPath            = $relativeCatalog
            InfFile                        = $infFile
            RelativeInfPath                = $relativeInf
            InstallerPath                  = $relativeInstaller
            BackupDriverFolder             = $relativeFolder
            PackageFileCount               = $packageFileCount
            HasAdditionalFiles             = $hasAdditionalFiles
            MissingFiles                   = @($missingFiles | Select-Object -Unique)
            ValidationMessages             = @($validationMessages)
            DriverStoreExported            = $driver.DriverStoreExported
            PackageExported                = $driver.PackageExported
            PackageExportSource            = $driver.PackageExportSource
            PackageValidation              = $driver.PackageValidation
            CatalogSignatureStatus         = if ($driver.CatalogSignatureStatus) { $driver.CatalogSignatureStatus } elseif ($signatureInfo) { $signatureInfo.SignatureStatus } else { '' }
            CatalogSignatureStatusMessage  = if ($driver.CatalogSignatureStatusMessage) { $driver.CatalogSignatureStatusMessage } elseif ($signatureInfo) { $signatureInfo.SignatureStatusMessage } else { '' }
            CatalogSignatureValid          = if ($signatureInfo) { [bool]$signatureInfo.IsTrusted } else { [bool]$driver.CatalogSignatureValid }
            CatalogCertificateTrusted      = if ($signatureInfo) { [bool]$signatureInfo.IsTrusted } else { [bool]$driver.CatalogCertificateTrusted }
            CatalogSignerSubject           = if ($driver.CatalogSignerSubject) { $driver.CatalogSignerSubject } elseif ($signatureInfo) { $signatureInfo.SignerSubject } else { '' }
            CatalogSignerIssuer            = if ($driver.CatalogSignerIssuer) { $driver.CatalogSignerIssuer } elseif ($signatureInfo) { $signatureInfo.SignerIssuer } else { '' }
            CatalogSignerThumbprint        = if ($driver.CatalogSignerThumbprint) { $driver.CatalogSignerThumbprint } elseif ($signatureInfo) { $signatureInfo.SignerThumbprint } else { '' }
            CatalogSignerNotBefore         = if ($driver.CatalogSignerNotBefore) { $driver.CatalogSignerNotBefore } elseif ($signatureInfo) { $signatureInfo.SignerNotBefore } else { '' }
            CatalogSignerNotAfter          = if ($driver.CatalogSignerNotAfter) { $driver.CatalogSignerNotAfter } elseif ($signatureInfo) { $signatureInfo.SignerNotAfter } else { '' }
            CatalogCertificateRelativePath = $driver.CatalogCertificateRelativePath
            Nome                           = $driver.Driver
            Versao                         = $driver.Versao
            Fabricante                     = $driver.Fabricante
            Arquitetura                    = $driver.Arquitetura
            DataBackup                     = $createdAt
            InfPath                        = $relativeInf
            PastaOrigem                    = $relativeFolder
            StatusBackup                   = $driver.Status
        }
    }

    [pscustomobject]@{
        SchemaVersion  = 2
        ServidorOrigem = Get-DriverVaultServerName
        DataBackup     = $createdAt
        BackupPath     = $BackupPath
        Drivers        = $items
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-DriverVaultLog ("Manifesto tecnico gerado: {0}" -f $manifestPath)
    return $manifestPath
}

function Invoke-RestoreInventoryProgress {
    param(
        [scriptblock]$ProgressCallback,
        [int]$Count,
        [string]$Message
    )

    if ($ProgressCallback) {
        try {
            & $ProgressCallback $Count $Message
        }
        catch {
            Write-DriverVaultLog ("Callback de progresso da listagem falhou: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
}

function Invoke-RestoreInventoryBatch {
    param(
        [scriptblock]$BatchCallback,
        [object[]]$Batch
    )

    if ($BatchCallback -and @($Batch).Count -gt 0) {
        try {
            $batchArgument = @($Batch)
            & $BatchCallback $batchArgument
        }
        catch {
            Write-DriverVaultLog ("Callback de lote da listagem falhou: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
}

function Test-RestoreInventoryCancelled {
    param(
        [scriptblock]$CancelCallback
    )

    if (-not $CancelCallback) {
        return $false
    }

    try {
        return [bool](& $CancelCallback)
    }
    catch {
        Write-DriverVaultLog ("Callback de cancelamento da listagem falhou: {0}" -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Find-DriverManifestFilesLightweight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupRoot,
        [int]$MaxManifestFiles = 500,
        [int]$MaxFolders = 20000,
        [scriptblock]$ProgressCallback,
        [scriptblock]$CancelCallback
    )

    $manifestFiles = @()
    $rootManifest = Join-Path $BackupRoot 'drivers-manifest.json'
    if (Test-Path -LiteralPath $rootManifest -PathType Leaf) {
        return @((Get-Item -LiteralPath $rootManifest))
    }

    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue((Resolve-Path -LiteralPath $BackupRoot).Path)
    $visitedFolders = 0

    while ($queue.Count -gt 0) {
        if (Test-RestoreInventoryCancelled -CancelCallback $CancelCallback) {
            Write-DriverVaultLog 'Busca de manifestos cancelada pelo usuario.' 'WARN'
            break
        }

        $folder = $queue.Dequeue()
        $visitedFolders++

        $candidate = Join-Path $folder 'drivers-manifest.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $manifestFiles += Get-Item -LiteralPath $candidate
            if ($manifestFiles.Count -ge $MaxManifestFiles) {
                Write-DriverVaultLog ("Limite de manifestos atingido na listagem leve: {0}" -f $MaxManifestFiles) 'WARN'
                break
            }
        }

        if ($visitedFolders -ge $MaxFolders) {
            Write-DriverVaultLog ("Limite de pastas atingido ao procurar manifestos: {0}" -f $MaxFolders) 'WARN'
            break
        }

        try {
            foreach ($child in @(Get-ChildItem -LiteralPath $folder -Directory -ErrorAction SilentlyContinue)) {
                $queue.Enqueue($child.FullName)
            }
        }
        catch {
            Write-DriverVaultLog ("Falha ao listar subpastas de {0}: {1}" -f $folder, $_.Exception.Message) 'WARN'
        }

        if (($visitedFolders % 100) -eq 0) {
            Invoke-RestoreInventoryProgress -ProgressCallback $ProgressCallback -Count $manifestFiles.Count -Message ("Procurando manifestos... pastas verificadas: {0}; manifestos: {1}" -f $visitedFolders, $manifestFiles.Count)
        }
    }

    return $manifestFiles
}

function Get-RestorableDriversFromManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    $backupPath = Split-Path -Parent $ManifestPath
    $records = @()
    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
        foreach ($item in @($manifest.Drivers)) {
            $selectedForBackup = Get-ObjectPropertyValue -Object $item -Names @('SelectedForBackup')
            $backupStatus = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('BackupStatus')) -Default ''
            $isInstallableValue = Get-ObjectPropertyValue -Object $item -Names @('IsInstallable')
            if (($null -ne $selectedForBackup -and -not [bool]$selectedForBackup) -or $backupStatus -eq 'Ignored') {
                continue
            }
            if ($backupStatus -eq 'Incomplete' -and $null -ne $isInstallableValue -and -not [bool]$isInstallableValue) {
                continue
            }

            $driverName = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('DriverName', 'Nome')) -Default 'Driver sem nome'
            $version = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('Version', 'Versao'))
            $manufacturer = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('Manufacturer', 'Fabricante'))
            $architecture = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('Architecture', 'Arquitetura'))
            $relativeInf = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('RelativeInfPath', 'InfPath')) -Default ''
            $relativeFolder = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('BackupDriverFolder', 'PastaOrigem')) -Default ''
            $infFile = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('InfFile')) -Default ''
            $originalInfName = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('OriginalInfName')) -Default ''
            $relativeInstaller = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('InstallerPath', 'RelativeInstallerPath')) -Default ''
            $certificateRelativePath = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('CatalogCertificateRelativePath')) -Default ''

            if ([string]::IsNullOrWhiteSpace($relativeInf) -and [string]::IsNullOrWhiteSpace($infFile) -and [string]::IsNullOrWhiteSpace($originalInfName) -and -not [string]::IsNullOrWhiteSpace($relativeInstaller)) {
                Write-DriverVaultLog ("Entrada de manifesto com instalador, mas sem INF, ignorada pela restauracao automatica: {0}" -f $driverName) 'WARN'
                continue
            }

            if ([string]::IsNullOrWhiteSpace($relativeInf) -and [string]::IsNullOrWhiteSpace($relativeFolder) -and [string]::IsNullOrWhiteSpace($infFile) -and [string]::IsNullOrWhiteSpace($originalInfName)) {
                Write-DriverVaultLog ("Entrada de manifesto ignorada por nao possuir INF/pasta de pacote: {0}" -f $driverName) 'WARN'
                continue
            }

            $folder = Resolve-BackupRelativePath -BackupPath $backupPath -RelativePath $relativeFolder
            $infPath = Resolve-BackupRelativePath -BackupPath $backupPath -RelativePath $relativeInf

            if ([string]::IsNullOrWhiteSpace($infFile) -and -not [string]::IsNullOrWhiteSpace($relativeInf)) {
                $infFile = [System.IO.Path]::GetFileName($relativeInf)
            }

            $infPathExists = (-not [string]::IsNullOrWhiteSpace($infPath) -and (Test-Path -LiteralPath $infPath -PathType Leaf))
            if (-not $infPathExists -and $folder -and (Test-Path -LiteralPath $folder -PathType Container) -and $infFile) {
                $candidate = Join-Path $folder $infFile
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $infPath = $candidate
                    $infPathExists = $true
                }
            }

            if (-not $infPathExists) {
                if ($infFile) {
                    $foundInf = Find-InfInBackup -BackupPath $backupPath -InfFile $infFile
                    if ($foundInf) {
                        $infPath = $foundInf
                        $infPathExists = $true
                    }
                }
            }

            if (-not $infPathExists) {
                $infFiles = @()
                if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) {
                    $infFiles = @(Get-ChildItem -LiteralPath $folder -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue)
                }
                if ($infFiles.Count -gt 0) {
                    $preferredInf = Find-PreferredInfFileInFolder -Folder $folder -Driver $item -AdditionalNames @($originalInfName, $infFile)
                    if ($preferredInf) {
                        $infPath = $preferredInf.FullName
                        $infFile = $preferredInf.Name
                        $infPathExists = $true
                    }
                    else {
                        $infPath = $infFiles[0].FullName
                        $infFile = $infFiles[0].Name
                        $infPathExists = $true
                    }
                }
            }

            if ($infPathExists) {
                $infPath = (Resolve-Path -LiteralPath $infPath).Path
                $folder = Split-Path -Parent $infPath
                $relativeInf = Get-RelativePathFromBase -BasePath $backupPath -TargetPath $infPath
            }

            $records += New-RestorableDriverWithDiagnostics `
                -Driver $driverName `
                -Fabricante $manufacturer `
                -Versao $version `
                -Arquitetura $architecture `
                -InfPath $infPath `
                -DriverFolder $folder `
                -BackupPath $backupPath `
                -Source 'Manifesto' `
                -RelativeInfPath $relativeInf `
                -InfFile $infFile `
                -CertificateRelativePath $certificateRelativePath
        }
    }
    catch {
        Write-DriverVaultLog ("Falha ao ler manifesto de restauracao {0}: {1}" -f $ManifestPath, $_.Exception.Message) 'WARN'
    }

    return $records
}

function New-RestorableDriverLightweight {
    param(
        [string]$Driver,
        [string]$Fabricante,
        [string]$Versao,
        [string]$Arquitetura,
        [string]$InfPath,
        [string]$DriverFolder,
        [string]$BackupPath,
        [string]$Source,
        [string]$RelativeInfPath = '',
        [string]$InfFile = '',
        [string]$RelativeCatalogPath = '',
        [string]$CertificateRelativePath = ''
    )

    if ([string]::IsNullOrWhiteSpace($InfFile) -and -not [string]::IsNullOrWhiteSpace($InfPath)) {
        $InfFile = [System.IO.Path]::GetFileName($InfPath)
    }

    $catalogPath = ''
    if (-not [string]::IsNullOrWhiteSpace($RelativeCatalogPath)) {
        $catalogPath = Resolve-BackupRelativePath -BackupPath $BackupPath -RelativePath $RelativeCatalogPath
    }

    $certificatePath = ''
    if (-not [string]::IsNullOrWhiteSpace($CertificateRelativePath)) {
        $certificatePath = Resolve-BackupRelativePath -BackupPath $BackupPath -RelativePath $CertificateRelativePath
    }

    $record = New-RestorableDriver `
        -Driver $Driver `
        -Fabricante $Fabricante `
        -Versao $Versao `
        -Arquitetura $Arquitetura `
        -InfPath $InfPath `
        -DriverFolder $DriverFolder `
        -BackupPath $BackupPath `
        -Source $Source `
        -RelativeInfPath $RelativeInfPath `
        -InfFile $InfFile `
        -InfExists $false `
        -DriverFolderExists $false `
        -HasAdditionalFiles $false `
        -PackageFileCount 0 `
        -MissingFiles @() `
        -CatalogPath $catalogPath `
        -RelativeCatalogPath $RelativeCatalogPath `
        -CatalogCertificatePath $certificatePath `
        -CatalogCertificateRelativePath $CertificateRelativePath `
        -IsInstallable $false `
        -IsValidated $false

    $record.Status = 'Pendente'
    $record.Avisos = 'Aguardando selecao para validacao.'
    return $record
}

function Get-RestorableDriversFromManifestLightweight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [int]$MaxRecords = 5000,
        [int]$BatchSize = 50,
        [scriptblock]$ProgressCallback,
        [scriptblock]$BatchCallback,
        [scriptblock]$CancelCallback
    )

    $backupPath = Split-Path -Parent $ManifestPath
    $records = @()
    $batch = @()
    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
        foreach ($item in @($manifest.Drivers)) {
            if (Test-RestoreInventoryCancelled -CancelCallback $CancelCallback) {
                Write-DriverVaultLog ("Listagem leve cancelada durante leitura do manifesto: {0}" -f $ManifestPath) 'WARN'
                break
            }
            $selectedForBackup = Get-ObjectPropertyValue -Object $item -Names @('SelectedForBackup')
            $backupStatus = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('BackupStatus')) -Default ''
            $isInstallableValue = Get-ObjectPropertyValue -Object $item -Names @('IsInstallable')
            if (($null -ne $selectedForBackup -and -not [bool]$selectedForBackup) -or $backupStatus -eq 'Ignored') {
                continue
            }
            if ($backupStatus -eq 'Incomplete' -and $null -ne $isInstallableValue -and -not [bool]$isInstallableValue) {
                continue
            }

            if ($records.Count -ge $MaxRecords) {
                Write-DriverVaultLog ("Limite de drivers atingido na leitura do manifesto {0}: {1}" -f $ManifestPath, $MaxRecords) 'WARN'
                break
            }

            $driverName = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('DriverName', 'Nome')) -Default 'Driver sem nome'
            $version = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('Version', 'Versao'))
            $manufacturer = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('Manufacturer', 'Fabricante'))
            $architecture = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('Architecture', 'Arquitetura'))
            $relativeInf = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('RelativeInfPath', 'InfPath')) -Default ''
            $relativeFolder = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('BackupDriverFolder', 'PastaOrigem')) -Default ''
            $infFile = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('InfFile', 'OriginalInfName')) -Default ''
            $relativeInstaller = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('InstallerPath', 'RelativeInstallerPath')) -Default ''
            $relativeCatalog = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('RelativeCatalogPath')) -Default ''
            $certificateRelativePath = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $item -Names @('CatalogCertificateRelativePath')) -Default ''

            if ([string]::IsNullOrWhiteSpace($relativeInf) -and [string]::IsNullOrWhiteSpace($infFile) -and -not [string]::IsNullOrWhiteSpace($relativeInstaller)) {
                Write-DriverVaultLog ("Entrada de manifesto com instalador, mas sem INF, ignorada pela listagem automatica de restauracao: {0}" -f $driverName) 'WARN'
                continue
            }

            if ([string]::IsNullOrWhiteSpace($relativeInf) -and [string]::IsNullOrWhiteSpace($relativeFolder) -and [string]::IsNullOrWhiteSpace($infFile)) {
                Write-DriverVaultLog ("Entrada de manifesto ignorada na listagem leve por nao possuir INF/pasta de pacote: {0}" -f $driverName) 'WARN'
                continue
            }

            $folder = Resolve-BackupRelativePath -BackupPath $backupPath -RelativePath $relativeFolder
            $infPath = Resolve-BackupRelativePath -BackupPath $backupPath -RelativePath $relativeInf
            if ([string]::IsNullOrWhiteSpace($infFile) -and -not [string]::IsNullOrWhiteSpace($relativeInf)) {
                $infFile = [System.IO.Path]::GetFileName($relativeInf)
            }

            $record = New-RestorableDriverLightweight `
                -Driver $driverName `
                -Fabricante $manufacturer `
                -Versao $version `
                -Arquitetura $architecture `
                -InfPath $infPath `
                -DriverFolder $folder `
                -BackupPath $backupPath `
                -Source 'Manifesto' `
                -RelativeInfPath $relativeInf `
                -InfFile $infFile `
                -RelativeCatalogPath $relativeCatalog `
                -CertificateRelativePath $certificateRelativePath

            $records += $record
            $batch += $record

            if ($batch.Count -ge $BatchSize) {
                Invoke-RestoreInventoryBatch -BatchCallback $BatchCallback -Batch $batch
                Invoke-RestoreInventoryProgress -ProgressCallback $ProgressCallback -Count $records.Count -Message ("Listando drivers pelo manifesto... {0} encontrados" -f $records.Count)
                $batch = @()
            }
        }

        Invoke-RestoreInventoryBatch -BatchCallback $BatchCallback -Batch $batch
        Invoke-RestoreInventoryProgress -ProgressCallback $ProgressCallback -Count $records.Count -Message ("Manifesto lido: {0} drivers disponiveis" -f $records.Count)
    } catch {
        Write-DriverVaultLog ("Falha ao ler manifesto de restauracao {0}: {1}" -f $ManifestPath, $_.Exception.Message) 'WARN'
    }

    return $records
}

function Get-RestorableDriversFromInfScanLightweight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [int]$MaxRecords = 5000,
        [int]$MaxFolders = 20000,
        [int]$BatchSize = 50,
        [scriptblock]$ProgressCallback,
        [scriptblock]$BatchCallback,
        [scriptblock]$CancelCallback
    )

    $records = @()
    $batch = @()
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue((Resolve-Path -LiteralPath $BackupPath).Path)
    $visitedFolders = 0

    while ($queue.Count -gt 0) {
        if (Test-RestoreInventoryCancelled -CancelCallback $CancelCallback) {
            Write-DriverVaultLog 'Varredura leve de INF cancelada pelo usuario.' 'WARN'
            break
        }

        if ($records.Count -ge $MaxRecords) {
            Write-DriverVaultLog ("Limite de drivers atingido na varredura leve de INF: {0}" -f $MaxRecords) 'WARN'
            break
        }

        $folderToScan = $queue.Dequeue()
        $visitedFolders++

        try {
            foreach ($inf in @(Get-ChildItem -LiteralPath $folderToScan -Filter *.inf -File -ErrorAction SilentlyContinue)) {
                if ($records.Count -ge $MaxRecords -or (Test-RestoreInventoryCancelled -CancelCallback $CancelCallback)) {
                    break
                }

                $folder = Split-Path -Parent $inf.FullName
                $relativeInf = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $inf.FullName
                $folderName = Split-Path -Leaf $folder
                $record = New-RestorableDriverLightweight `
                    -Driver $folderName `
                    -Fabricante 'N/D' `
                    -Versao 'N/D' `
                    -Arquitetura $env:PROCESSOR_ARCHITECTURE `
                    -InfPath $inf.FullName `
                    -DriverFolder $folder `
                    -BackupPath $BackupPath `
                    -Source 'Varredura INF leve' `
                    -RelativeInfPath $relativeInf `
                    -InfFile $inf.Name

                $records += $record
                $batch += $record

                if ($batch.Count -ge $BatchSize) {
                    Invoke-RestoreInventoryBatch -BatchCallback $BatchCallback -Batch $batch
                    Invoke-RestoreInventoryProgress -ProgressCallback $ProgressCallback -Count $records.Count -Message ("Varredura leve de INF... {0} drivers encontrados" -f $records.Count)
                    $batch = @()
                }
            }

            foreach ($child in @(Get-ChildItem -LiteralPath $folderToScan -Directory -ErrorAction SilentlyContinue)) {
                $queue.Enqueue($child.FullName)
            }
        }
        catch {
            Write-DriverVaultLog ("Falha na varredura leve da pasta {0}: {1}" -f $folderToScan, $_.Exception.Message) 'WARN'
        }

        if ($visitedFolders -ge $MaxFolders) {
            Write-DriverVaultLog ("Limite de pastas atingido na varredura leve de INF: {0}" -f $MaxFolders) 'WARN'
            break
        }

        if (($visitedFolders % 100) -eq 0) {
            Invoke-RestoreInventoryProgress -ProgressCallback $ProgressCallback -Count $records.Count -Message ("Varredura leve de INF... pastas: {0}; drivers: {1}" -f $visitedFolders, $records.Count)
        }
    }

    Invoke-RestoreInventoryBatch -BatchCallback $BatchCallback -Batch $batch
    Invoke-RestoreInventoryProgress -ProgressCallback $ProgressCallback -Count $records.Count -Message ("Varredura leve concluida: {0} drivers encontrados" -f $records.Count)
    return $records
}

function Get-RestorableDriversFromInfScan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    $records = @()
    $infFiles = @(Get-ChildItem -LiteralPath $BackupPath -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue)
    foreach ($inf in $infFiles) {
        $metadata = Get-InfMetadata -InfPath $inf.FullName
        $folder = Split-Path -Parent $inf.FullName
        $relativeInf = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $inf.FullName
        $records += New-RestorableDriverWithDiagnostics `
            -Driver $metadata.Driver `
            -Fabricante $metadata.Fabricante `
            -Versao $metadata.Versao `
            -Arquitetura $metadata.Arquitetura `
            -InfPath $inf.FullName `
            -DriverFolder $folder `
            -BackupPath $BackupPath `
            -Source 'Varredura INF' `
            -RelativeInfPath $relativeInf `
            -InfFile $inf.Name
    }
    return $records
}

function Get-RestorableDriversFromBackup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupRoot,
        [switch]$DeepValidation,
        [int]$MaxRecords = 5000,
        [int]$BatchSize = 50,
        [int]$MaxManifestFiles = 500,
        [scriptblock]$ProgressCallback,
        [scriptblock]$BatchCallback,
        [scriptblock]$CancelCallback
    )

    if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
        throw "A pasta de backup nao existe: $BackupRoot"
    }

    $records = @()
    Invoke-RestoreInventoryProgress -ProgressCallback $ProgressCallback -Count 0 -Message 'Etapa 1: listagem leve de drivers disponiveis...'

    $manifestFiles = @(Find-DriverManifestFilesLightweight `
            -BackupRoot $BackupRoot `
            -MaxManifestFiles $MaxManifestFiles `
            -ProgressCallback $ProgressCallback `
            -CancelCallback $CancelCallback)

    if ($manifestFiles.Count -gt 0) {
        Write-DriverVaultLog ("Manifestos encontrados para restauracao: {0}" -f $manifestFiles.Count)
    }
    else {
        Write-DriverVaultLog 'Nenhum drivers-manifest.json encontrado. Usando varredura leve por INF.' 'WARN'
    }

    foreach ($manifestFile in $manifestFiles) {
        if (Test-RestoreInventoryCancelled -CancelCallback $CancelCallback) {
            Write-DriverVaultLog 'Listagem de restauracao cancelada antes de processar todos os manifestos.' 'WARN'
            break
        }
        if ($records.Count -ge $MaxRecords) {
            Write-DriverVaultLog ("Limite total de drivers atingido na listagem: {0}" -f $MaxRecords) 'WARN'
            break
        }

        $remaining = [Math]::Max(($MaxRecords - $records.Count), 0)
        if ($DeepValidation) {
            $records += @(Get-RestorableDriversFromManifest -ManifestPath $manifestFile.FullName | Select-Object -First $remaining)
        } else {
            $records += @(Get-RestorableDriversFromManifestLightweight `
                    -ManifestPath $manifestFile.FullName `
                    -MaxRecords $remaining `
                    -BatchSize $BatchSize `
                    -ProgressCallback $ProgressCallback `
                    -BatchCallback $BatchCallback `
                    -CancelCallback $CancelCallback)
        }

        Invoke-RestoreInventoryProgress -ProgressCallback $ProgressCallback -Count $records.Count -Message ("Listagem leve: {0} drivers encontrados" -f $records.Count)
    }

    $knownInfPaths = @{}
    if ($manifestFiles.Count -eq 0 -or $DeepValidation) {
        foreach ($record in @($records)) {
            if ($record.InfPath -and (Test-Path -LiteralPath $record.InfPath -PathType Leaf)) {
                $knownInfPaths[(Resolve-Path -LiteralPath $record.InfPath).Path.ToLowerInvariant()] = $true
            }
        }
    }

    if ($manifestFiles.Count -eq 0 -or $DeepValidation) {
        if (Test-RestoreInventoryCancelled -CancelCallback $CancelCallback) {
            Write-DriverVaultLog 'Varredura INF ignorada porque a listagem foi cancelada.' 'WARN'
        }
        elseif ($records.Count -lt $MaxRecords) {
            $remaining = [Math]::Max(($MaxRecords - $records.Count), 0)
        $scanRecords = if ($DeepValidation) {
            @(Get-RestorableDriversFromInfScan -BackupPath $BackupRoot | Select-Object -First $remaining)
        } else {
            @(Get-RestorableDriversFromInfScanLightweight `
                    -BackupPath $BackupRoot `
                    -MaxRecords $remaining `
                    -BatchSize $BatchSize `
                    -ProgressCallback $ProgressCallback `
                    -BatchCallback $BatchCallback `
                    -CancelCallback $CancelCallback)
        }

        foreach ($record in $scanRecords) {
            $key = ''
            if ($record.InfPath -and (Test-Path -LiteralPath $record.InfPath -PathType Leaf)) {
                $key = (Resolve-Path -LiteralPath $record.InfPath).Path.ToLowerInvariant()
            }
            if (-not $key -or -not $knownInfPaths.ContainsKey($key)) {
                $records += $record
                if ($key) {
                    $knownInfPaths[$key] = $true
                }
            }
        }
        }
    }

    if ($records.Count -eq 0 -and (Test-RestoreInventoryCancelled -CancelCallback $CancelCallback)) {
        Write-DriverVaultLog 'Listagem de restauracao encerrada sem registros porque foi cancelada pelo usuario.' 'WARN'
        return @()
    }

    if ($records.Count -eq 0) {
        throw "Nenhum driver com arquivo INF foi encontrado em: $BackupRoot"
    }

    Invoke-RestoreInventoryProgress -ProgressCallback $ProgressCallback -Count $records.Count -Message ("Listagem leve concluida: {0} drivers encontrados" -f $records.Count)
    Write-DriverVaultLog ("Total de drivers encontrados na listagem leve: {0}" -f $records.Count)
    return @($records | Sort-Object Driver, Versao, Arquitetura, InfPath)
}
