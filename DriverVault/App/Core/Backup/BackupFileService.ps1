# Modulo extraido de BackupService.ps1.



function Copy-DriverFileSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder,
        [switch]$SkipIfExists
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-DriverVaultLog ("Arquivo nao encontrado para copia: {0}" -f $SourcePath) 'WARN'
        return [pscustomobject]@{ Copied = $false; Destination = ''; Error = 'Arquivo nao encontrado' }
    }

    if (-not (Test-Path -LiteralPath $DestinationFolder)) {
        New-Item -ItemType Directory -Force -Path $DestinationFolder | Out-Null
    }

    $fileName = [System.IO.Path]::GetFileName($SourcePath)
    $destination = Join-Path $DestinationFolder $fileName

    if (Test-Path -LiteralPath $destination) {
        if ($SkipIfExists) {
            return [pscustomobject]@{ Copied = $false; Destination = $destination; Error = ''; Skipped = $true }
        }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $ext = [System.IO.Path]::GetExtension($fileName)
        for ($i = 2; $i -lt 1000; $i++) {
            $candidate = Join-Path $DestinationFolder ("{0}_{1}{2}" -f $base, $i, $ext)
            if (-not (Test-Path -LiteralPath $candidate)) {
                $destination = $candidate
                break
            }
        }
        Write-DriverVaultLog ("Arquivo ja existia no destino. Salvando com nome unico: {0}" -f $destination) 'WARN'
    }

    try {
        Copy-Item -LiteralPath $SourcePath -Destination $destination -Force:$false -ErrorAction Stop
        Write-DriverVaultLog ("Arquivo copiado: {0} -> {1}" -f $SourcePath, $destination)
        return [pscustomobject]@{ Copied = $true; Destination = $destination; Error = '' }
    }
    catch {
        Write-DriverVaultLog ("Erro ao copiar {0}: {1}" -f $SourcePath, $_.Exception.Message) 'ERROR'
        return [pscustomobject]@{ Copied = $false; Destination = $destination; Error = $_.Exception.Message }
    }
}

function Copy-DirectoryContentsSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
        return 0
    }
    if (-not (Test-Path -LiteralPath $DestinationFolder)) {
        New-Item -ItemType Directory -Force -Path $DestinationFolder | Out-Null
    }

    $sourceRoot = (Resolve-Path -LiteralPath $SourceFolder).Path
    $copied = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -ErrorAction SilentlyContinue)) {
        $relative = Get-RelativePathFromBase -BasePath $sourceRoot -TargetPath $file.FullName
        $destination = Join-Path $DestinationFolder $relative
        $destinationParent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationParent)) {
            New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
        }

        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            continue
        }

        try {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force:$false -ErrorAction Stop
            $copied++
        }
        catch {
            Write-DriverVaultLog ("Erro ao copiar arquivo de pacote {0}: {1}" -f $file.FullName, $_.Exception.Message) 'WARN'
        }
    }
    return $copied
}

function Copy-AdditionalDriverPackageFolders {
    param(
        [string[]]$SourceFiles,
        [string]$TargetFolder
    )

    $copied = 0
    foreach ($folder in @(Get-AdditionalPackageFolders -SourceFiles $SourceFiles)) {
        Write-DriverVaultLog ("Copiando pasta complementar do pacote de driver: {0}" -f $folder)
        $copied += Copy-DirectoryContentsSafe -SourceFolder $folder -DestinationFolder $TargetFolder
    }
    return $copied
}

function Copy-PnPUtilPackageFromDriverStore {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Package,
        [Parameter(Mandatory = $true)]
        [string]$TargetFolder
    )

    $copied = 0
    $infRefs = @()
    foreach ($name in @($Package.OriginalName, $Package.PublishedName)) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $infRefs += $name
        }
    }

    foreach ($folder in @(Get-DriverStorePackageFolders -SourceFiles ($infRefs | Select-Object -Unique))) {
        Write-DriverVaultLog ("Copiando pacote do DriverStore com base no pnputil: {0}" -f $folder)
        $copied += Copy-DirectoryContentsSafe -SourceFolder $folder -DestinationFolder $TargetFolder
    }
    return $copied
}

function Write-DriverVaultSourceDiagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver,
        [string[]]$SourceFiles
    )

    $spoolRoot = Join-Path $env:windir 'System32\spool\drivers'
    $driverStoreRoot = Join-Path $env:windir 'System32\DriverStore\FileRepository'
    $spoolFiles = @($SourceFiles | Where-Object { Test-IsUnderPath -Path $_ -ParentPath $spoolRoot })
    $driverStoreFiles = @($SourceFiles | Where-Object { Test-IsUnderPath -Path $_ -ParentPath $driverStoreRoot })
    $infFiles = @($SourceFiles | Where-Object { [System.IO.Path]::GetExtension($_) -ieq '.inf' })
    $catFiles = @($SourceFiles | Where-Object { [System.IO.Path]::GetExtension($_) -ieq '.cat' })

    Write-DriverVaultLog ("Diagnostico de origem do driver selecionado: Nome={0}; Fabricante={1}; Versao={2}; Arquitetura={3}; Origem={4}; SourceInfPath={5}; PublishedName={6}; OriginalInfName={7}; ArquivosFonte={8}; Spooler={9}; DriverStore={10}; INF fonte={11}; CAT fonte={12}" -f $Driver.Driver, $Driver.Fabricante, $Driver.Versao, $Driver.Arquitetura, $Driver.Origem, (ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @('SourceInfPath')) -Default ''), $Driver.PublishedName, $Driver.OriginalInfName, @($SourceFiles).Count, $spoolFiles.Count, $driverStoreFiles.Count, $infFiles.Count, $catFiles.Count)

    foreach ($file in @($SourceFiles | Select-Object -First 40)) {
        $sourceKind = 'Outro'
        if (Test-IsUnderPath -Path $file -ParentPath $driverStoreRoot) {
            $sourceKind = 'DriverStore'
        }
        elseif (Test-IsUnderPath -Path $file -ParentPath $spoolRoot) {
            $sourceKind = 'Spooler'
        }
        Write-DriverVaultLog ("Origem do arquivo do driver: Tipo={0}; Caminho={1}" -f $sourceKind, $file)
    }
    if (@($SourceFiles).Count -gt 40) {
        Write-DriverVaultLog ("Origem do driver possui mais arquivos; exibidos 40 de {0}." -f @($SourceFiles).Count)
    }
}

function Set-DriverVaultObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [object]$Value
    )

    if ($Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties[$Name].Value = $Value
    }
    else {
        Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function Find-DriverInstallerCandidate {
    param(
        [string]$DriverFolder
    )

    if ([string]::IsNullOrWhiteSpace($DriverFolder) -or -not (Test-Path -LiteralPath $DriverFolder -PathType Container)) {
        return $null
    }

    $patterns = @('*.msi', 'setup*.exe', 'install*.exe', 'installer*.exe')
    foreach ($pattern in $patterns) {
        $match = Get-ChildItem -LiteralPath $DriverFolder -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            Select-Object -First 1
        if ($match) {
            return $match
        }
    }

    return $null
}

function Set-DriverVaultPackageValidation {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver,
        [Parameter(Mandatory = $true)]
        [string]$DriverFolder,
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [string[]]$AdditionalInfNames = @(),
        [int]$CopiedFiles = 0,
        [string[]]$Errors = @()
    )

    $messages = @()
    $isInstallable = $true
    $primaryInf = $null
    $packageFiles = @()
    $catalogFiles = @()
    $relativeFolder = ''
    $relativeInf = ''
    $relativeCatalog = ''
    $catalogPath = ''
    $installer = $null

    if ([string]::IsNullOrWhiteSpace($DriverFolder) -or -not (Test-Path -LiteralPath $DriverFolder -PathType Container)) {
        $isInstallable = $false
        $messages += 'A pasta do driver nao foi criada no backup.'
    }
    else {
        $driverFolderFull = (Resolve-Path -LiteralPath $DriverFolder).Path
        $relativeFolder = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $driverFolderFull
        $packageFiles = @(Get-ChildItem -LiteralPath $driverFolderFull -Recurse -File -ErrorAction SilentlyContinue)
        $primaryInf = Find-PreferredInfFileInFolder -Folder $driverFolderFull -Driver $Driver -AdditionalNames $AdditionalInfNames
        $installer = Find-DriverInstallerCandidate -DriverFolder $driverFolderFull

        if ($packageFiles.Count -eq 0) {
            $isInstallable = $false
            $messages += 'O pacote exportado esta vazio.'
        }

        if ($primaryInf) {
            $primaryInf = Get-Item -LiteralPath $primaryInf.FullName
            $relativeInf = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $primaryInf.FullName
            Set-DriverVaultObjectProperty -Object $Driver -Name 'PrimaryInfPath' -Value $primaryInf.FullName
            Set-DriverVaultObjectProperty -Object $Driver -Name 'RelativeInfPath' -Value $relativeInf
            if ([string]::IsNullOrWhiteSpace($Driver.OriginalInfName)) {
                Set-DriverVaultObjectProperty -Object $Driver -Name 'OriginalInfName' -Value $primaryInf.Name
            }

            Repair-MissingCatalogFilesFromBackup -InfPath $primaryInf.FullName -DriverFolder (Split-Path -Parent $primaryInf.FullName) -BackupPath $driverFolderFull
            $catalogFiles = @(Get-InfCatalogFiles -InfPath $primaryInf.FullName)
            $missingCatalogs = @()
            foreach ($catalog in $catalogFiles) {
                $candidateCatalog = Join-Path (Split-Path -Parent $primaryInf.FullName) $catalog
                if (-not (Test-Path -LiteralPath $candidateCatalog -PathType Leaf)) {
                    $foundCatalog = Get-ChildItem -LiteralPath $driverFolderFull -Recurse -File -Filter $catalog -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($foundCatalog) {
                        $candidateCatalog = $foundCatalog.FullName
                    }
                }

                if (-not (Test-Path -LiteralPath $candidateCatalog -PathType Leaf)) {
                    $missingCatalogs += $catalog
                }
                elseif ([string]::IsNullOrWhiteSpace($catalogPath)) {
                    $catalogPath = (Resolve-Path -LiteralPath $candidateCatalog).Path
                    $relativeCatalog = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $catalogPath
                }
            }

            if ($missingCatalogs.Count -gt 0) {
                $isInstallable = $false
                $messages += ('Catalogo(s) referenciado(s) pelo INF nao encontrado(s): {0}' -f ($missingCatalogs -join ', '))
            }

            if ($packageFiles.Count -le 1) {
                $isInstallable = $false
                $messages += 'O pacote nao possui arquivos auxiliares alem do INF.'
            }

            Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogFiles' -Value @($catalogFiles)
            Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogPath' -Value $catalogPath
            Set-DriverVaultObjectProperty -Object $Driver -Name 'RelativeCatalogPath' -Value $relativeCatalog

            if ($catalogPath) {
                $signature = Get-DriverCatalogSignatureInfo -CatalogPath $catalogPath
                Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogSignatureStatus' -Value $signature.SignatureStatus
                Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogSignatureStatusMessage' -Value $signature.SignatureStatusMessage
                Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogSignatureValid' -Value ([bool]$signature.IsTrusted)
                Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogCertificateTrusted' -Value ([bool]$signature.IsTrusted)
                Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogSignerSubject' -Value $signature.SignerSubject
                Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogSignerIssuer' -Value $signature.SignerIssuer
                Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogSignerThumbprint' -Value $signature.SignerThumbprint
                Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogSignerNotBefore' -Value $signature.SignerNotBefore
                Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogSignerNotAfter' -Value $signature.SignerNotAfter

                if ($signature.IsSigned) {
                    $certExport = Export-DriverCatalogCertificate -CatalogPath $catalogPath -DestinationFolder (Join-Path $BackupPath 'Certificates')
                    if ($certExport.Exported) {
                        Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogCertificatePath' -Value $certExport.CertificatePath
                        Set-DriverVaultObjectProperty -Object $Driver -Name 'CatalogCertificateRelativePath' -Value (Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $certExport.CertificatePath)
                    }
                }

                if (-not $signature.IsTrusted) {
                    $messages += ("Catalogo encontrado, mas assinatura/certificado nao confiavel: {0}" -f $signature.SignatureStatus)
                    Write-DriverVaultLog ("Catalogo com assinatura/certificado nao confiavel para {0}. Status={1}; Thumbprint={2}" -f $Driver.Driver, $signature.SignatureStatus, $signature.SignerThumbprint) 'WARN'
                }
            }
        }
        elseif ($installer) {
            $installer = Get-Item -LiteralPath $installer.FullName
            Set-DriverVaultObjectProperty -Object $Driver -Name 'InstallerPath' -Value $installer.FullName
            Set-DriverVaultObjectProperty -Object $Driver -Name 'RelativeInstallerPath' -Value (Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $installer.FullName)
            $messages += ("Nenhum INF foi encontrado, mas um instalador detectavel foi localizado: {0}" -f $installer.Name)
        }
        else {
            $isInstallable = $false
            $messages += 'Backup incompleto: o pacote instalavel deste driver nao foi localizado.'
            if ($packageFiles.Count -gt 0) {
                $messages += 'Foram encontrados arquivos operacionais, mas nenhum arquivo .inf ou instalador valido.'
            }
            $messages += 'Nenhum arquivo .inf foi encontrado no pacote exportado.'
            $messages += 'Esse driver nao podera ser restaurado em outro servidor.'
        }
    }

    foreach ($errorMessage in @($Errors | Where-Object { $_ })) {
        $messages += ("Falha ao copiar arquivo auxiliar: {0}" -f $errorMessage)
    }

    Set-DriverVaultObjectProperty -Object $Driver -Name 'CaminhoBackup' -Value $DriverFolder
    Set-DriverVaultObjectProperty -Object $Driver -Name 'BackupDriverFolder' -Value $relativeFolder
    Set-DriverVaultObjectProperty -Object $Driver -Name 'ArquivosCopiados' -Value $CopiedFiles
    Set-DriverVaultObjectProperty -Object $Driver -Name 'IsInstallable' -Value ([bool]$isInstallable)
    Set-DriverVaultObjectProperty -Object $Driver -Name 'ValidationMessages' -Value @($messages | Where-Object { $_ } | Select-Object -Unique)

    $validatedInfFiles = @()
    $validatedCatFiles = @()
    if ($DriverFolder -and (Test-Path -LiteralPath $DriverFolder -PathType Container)) {
        $validatedInfFiles = @(Get-ChildItem -LiteralPath $DriverFolder -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue)
        $validatedCatFiles = @(Get-ChildItem -LiteralPath $DriverFolder -Recurse -Filter *.cat -File -ErrorAction SilentlyContinue)
    }
    Write-DriverVaultLog ("Validacao final do pacote: Driver={0}; Pasta={1}; Arquivos={2}; INF encontrados={3}; CAT encontrados={4}; Instalador={5}; IsInstallable={6}; Mensagens={7}" -f $Driver.Driver, $DriverFolder, $packageFiles.Count, $validatedInfFiles.Count, $validatedCatFiles.Count, $(if ($installer) { $installer.FullName } else { '' }), [bool]$isInstallable, ((@($messages | Where-Object { $_ } | Select-Object -Unique)) -join ' | '))

    if ($isInstallable) {
        Set-DriverVaultObjectProperty -Object $Driver -Name 'BackupStatus' -Value 'Success'
        Set-DriverVaultObjectProperty -Object $Driver -Name 'Status' -Value 'Backup concluido'
        if ($messages.Count -eq 0) {
            Set-DriverVaultObjectProperty -Object $Driver -Name 'PackageValidation' -Value 'Pacote validado'
        }
        else {
            Set-DriverVaultObjectProperty -Object $Driver -Name 'PackageValidation' -Value (($messages | Select-Object -Unique) -join ' | ')
            Set-DriverVaultObjectProperty -Object $Driver -Name 'Avisos' -Value ((@($Driver.Avisos) + $messages | Where-Object { $_ }) -join ' | ')
        }
    }
    else {
        Set-DriverVaultObjectProperty -Object $Driver -Name 'BackupStatus' -Value 'Incomplete'
        Set-DriverVaultObjectProperty -Object $Driver -Name 'Status' -Value 'Backup incompleto'
        Set-DriverVaultObjectProperty -Object $Driver -Name 'PackageValidation' -Value ('Backup incompleto: ' + (($messages | Select-Object -Unique) -join ' | '))
        Set-DriverVaultObjectProperty -Object $Driver -Name 'Avisos' -Value ((@($Driver.Avisos) + $messages | Where-Object { $_ }) -join ' | ')
    }

    return [pscustomobject]@{
        IsInstallable      = [bool]$isInstallable
        PrimaryInfPath     = if ($primaryInf) { $primaryInf.FullName } else { '' }
        RelativeInfPath    = $relativeInf
        CatalogFiles       = @($catalogFiles)
        CatalogPath        = $catalogPath
        RelativeCatalogPath = $relativeCatalog
        InstallerPath      = if ($installer) { $installer.FullName } else { '' }
        ValidationMessages = @($messages | Where-Object { $_ } | Select-Object -Unique)
    }
}

function Copy-DriverFiles {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver,
        [Parameter(Mandatory = $true)]
        [string]$DriversRoot,
        [switch]$SalvarSeparado
    )

    $driverFolderName = '{0}_{1}' -f (ConvertTo-SafeFileName -Name $Driver.Driver), (ConvertTo-SafeFileName -Name $Driver.Versao -MaxLength 40)
    if ($SalvarSeparado) {
        $targetFolder = Join-Path (Join-Path $DriversRoot 'Duplicados') $driverFolderName
    }
    else {
        $targetFolder = Join-Path $DriversRoot $driverFolderName
    }
    $targetFolder = Get-UniqueDirectoryPath -Path $targetFolder
    New-Item -ItemType Directory -Force -Path $targetFolder | Out-Null

    $Driver.CaminhoBackup = $targetFolder
    $copied = 0
    $errors = @()
    $sourceFiles = @($Driver.CaminhosArquivos | Where-Object { $_ } | Select-Object -Unique)
    $infNames = @(Get-InfNamesFromSourceFiles -SourceFiles $sourceFiles)
    $backupRoot = Split-Path -Parent $DriversRoot
    Write-DriverVaultSourceDiagnostics -Driver $Driver -SourceFiles $sourceFiles

    $pnputilPackage = Find-PnPUtilPackageForDriver -Driver $Driver -SourceFiles $sourceFiles
    if ($pnputilPackage) {
        $Driver.PublishedName = $pnputilPackage.PublishedName
        $Driver.OriginalInfName = $pnputilPackage.OriginalName
        $Driver.DriverPackageProvider = $pnputilPackage.Provider
        $Driver.DriverPackageClass = $pnputilPackage.ClassName
        $Driver.DriverPackageVersion = $pnputilPackage.DriverVersion

        Write-DriverVaultLog ("Exportando pacote completo com pnputil: Driver={0}; PublishedName={1}; OriginalName={2}" -f $Driver.Driver, $pnputilPackage.PublishedName, $pnputilPackage.OriginalName)
        $exportResult = Export-DriverPackageWithPnPUtil -Package $pnputilPackage -TargetFolder $targetFolder
        if ($exportResult.Exported) {
            $Driver.PackageExported = $true
            $Driver.DriverStoreExported = $true
            $Driver.PackageExportSource = 'pnputil /export-driver'
            $copied += $exportResult.FilesCopied
            Write-DriverVaultLog ("Pacote exportado com pnputil para {0}. Arquivos copiados: {1}" -f $Driver.Driver, $exportResult.FilesCopied)
            $exportedInfCount = @(Get-ChildItem -LiteralPath $targetFolder -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue).Count
            $exportedCatCount = @(Get-ChildItem -LiteralPath $targetFolder -Recurse -Filter *.cat -File -ErrorAction SilentlyContinue).Count
            Write-DriverVaultLog ("Resultado pnputil /export-driver: Driver={0}; PublishedName={1}; OriginalName={2}; INF no destino={3}; CAT no destino={4}" -f $Driver.Driver, $pnputilPackage.PublishedName, $pnputilPackage.OriginalName, $exportedInfCount, $exportedCatCount)
        }
        else {
            $Driver.PackageExported = $false
            $Driver.PackageExportSource = 'Fallback manual'
            Write-DriverVaultLog ("Nao foi possivel exportar pacote com pnputil para {0}: {1}" -f $Driver.Driver, $exportResult.Error) 'WARN'
            $driverStoreCopied = Copy-PnPUtilPackageFromDriverStore -Package $pnputilPackage -TargetFolder $targetFolder
            if ($driverStoreCopied -gt 0) {
                $Driver.DriverStoreExported = $true
                $Driver.PackageExportSource = 'DriverStore fallback via pnputil'
                $copied += $driverStoreCopied
                Write-DriverVaultLog ("Pacote copiado do DriverStore para {0}. Arquivos copiados: {1}" -f $Driver.Driver, $driverStoreCopied)
            }
        }
    }

    if ($sourceFiles.Count -eq 0 -and $copied -eq 0) {
        Write-DriverVaultLog ("Nenhum pacote exportavel localizado para o driver {0}" -f $Driver.Driver) 'WARN'
        Set-DriverVaultPackageValidation -Driver $Driver -DriverFolder $targetFolder -BackupPath $backupRoot -AdditionalInfNames $infNames -CopiedFiles 0 -Errors @() | Out-Null
        return [pscustomobject]@{ Driver = $Driver; CopiedFiles = 0; Errors = @(); TargetFolder = $targetFolder }
    }

    foreach ($file in $sourceFiles) {
        $result = Copy-DriverFileSafe -SourcePath $file -DestinationFolder $targetFolder -SkipIfExists
        if ($result.Copied) {
            $copied++
        }
        elseif ($result.Error) {
            $errors += ("{0}: {1}" -f $file, $result.Error)
        }
    }

    $packageCopied = Copy-AdditionalDriverPackageFolders -SourceFiles $sourceFiles -TargetFolder $targetFolder
    if ($packageCopied -gt 0) {
        $copied += $packageCopied
        Write-DriverVaultLog ("Arquivos complementares de pacote copiados para {0}: {1}" -f $Driver.Driver, $packageCopied)
    }

    Set-DriverVaultPackageValidation -Driver $Driver -DriverFolder $targetFolder -BackupPath $backupRoot -AdditionalInfNames $infNames -CopiedFiles $copied -Errors $errors | Out-Null
    if ($errors.Count -gt 0) {
        $Driver.Erros = ($errors -join ' | ')
    }

    if ($Driver.BackupStatus -eq 'Incomplete') {
        Write-DriverVaultLog ("Backup incompleto para {0}: {1}" -f $Driver.Driver, (@($Driver.ValidationMessages) -join ' | ')) 'WARN'
    }
    elseif ($Driver.BackupStatus -eq 'Success') {
        Write-DriverVaultLog ("Backup validado como instalavel para {0}. INF={1}; Instalador={2}" -f $Driver.Driver, $Driver.PrimaryInfPath, $Driver.InstallerPath)
    }

    return [pscustomobject]@{ Driver = $Driver; CopiedFiles = $copied; Errors = $errors; TargetFolder = $targetFolder }
}
