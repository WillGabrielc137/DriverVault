# Modulo extraido de RestoreService.ps1.



function Find-InfInBackup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [string]$InfFile
    )

    if ([string]::IsNullOrWhiteSpace($InfFile) -or -not (Test-Path -LiteralPath $BackupPath -PathType Container)) {
        return ''
    }

    $match = Get-ChildItem -LiteralPath $BackupPath -Recurse -Filter $InfFile -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) {
        return $match.FullName
    }
    return ''
}

function Get-InfCatalogFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InfPath
    )

    $catalogs = @()
    if (-not (Test-Path -LiteralPath $InfPath -PathType Leaf)) {
        return $catalogs
    }

    try {
        foreach ($line in (Get-Content -LiteralPath $InfPath -ErrorAction Stop)) {
            if ($line -match '^\s*CatalogFile(?:\.[^=]+)?\s*=\s*(.+)\s*$') {
                $catalog = $matches[1].Trim().Trim('"')
                if (-not [string]::IsNullOrWhiteSpace($catalog)) {
                    $catalogs += $catalog
                }
            }
        }
    }
    catch {
        Write-DriverVaultLog ("Falha ao ler catalogos do INF {0}: {1}" -f $InfPath, $_.Exception.Message) 'WARN'
    }

    return @($catalogs | Select-Object -Unique)
}

function Get-PreferredInfNames {
    param(
        [object]$Driver,
        [string[]]$AdditionalNames = @()
    )

    $names = @()
    foreach ($property in @('OriginalInfName', 'InfFile', 'PublishedName')) {
        if ($Driver) {
            $value = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @($property)) -Default ''
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $names += [System.IO.Path]::GetFileName($value)
            }
        }
    }

    foreach ($name in @($AdditionalNames)) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $names += [System.IO.Path]::GetFileName($name)
        }
    }

    return @($names |
        Where-Object { $_ -and ([System.IO.Path]::GetExtension($_) -ieq '.inf') } |
        Select-Object -Unique)
}

function Find-PreferredInfFileInFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [object]$Driver,
        [string[]]$AdditionalNames = @()
    )

    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
        return $null
    }

    $infFiles = @(Get-ChildItem -LiteralPath $Folder -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue)
    if ($infFiles.Count -eq 0) {
        return $null
    }

    foreach ($name in (Get-PreferredInfNames -Driver $Driver -AdditionalNames $AdditionalNames)) {
        $match = $infFiles | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($match) {
            return $match
        }
    }

    return $infFiles[0]
}

function Get-RestorablePackageDiagnostics {
    param(
        [string]$InfPath,
        [string]$DriverFolder
    )

    $infFullPath = Resolve-FullPathIfExists -Path $InfPath
    $folderFullPath = Resolve-FullPathIfExists -Path $DriverFolder
    $infExists = (-not [string]::IsNullOrWhiteSpace($infFullPath) -and (Test-Path -LiteralPath $infFullPath -PathType Leaf))
    $folderExists = (-not [string]::IsNullOrWhiteSpace($folderFullPath) -and (Test-Path -LiteralPath $folderFullPath -PathType Container))
    $fileCount = 0
    $hasAdditionalFiles = $false
    $missingFiles = @()
    $catalogFiles = @()
    $catalogPath = ''
    $signature = $null

    if ($folderExists) {
        $files = @(Get-ChildItem -LiteralPath $folderFullPath -Recurse -File -ErrorAction SilentlyContinue)
        $fileCount = $files.Count
        $hasAdditionalFiles = ($files | Where-Object { $_.FullName -ne $infFullPath } | Select-Object -First 1) -ne $null
    }

    if ($infExists -and $folderExists) {
        $catalogFiles = @(Get-InfCatalogFiles -InfPath $infFullPath)
        foreach ($catalog in $catalogFiles) {
            $candidateCatalogPath = Join-Path $folderFullPath $catalog
            if (-not (Test-Path -LiteralPath $candidateCatalogPath -PathType Leaf)) {
                $missingFiles += $catalog
            }
            elseif ([string]::IsNullOrWhiteSpace($catalogPath)) {
                $catalogPath = (Resolve-Path -LiteralPath $candidateCatalogPath).Path
            }
        }
    }

    if ($catalogPath) {
        $signature = Get-DriverCatalogSignatureInfo -CatalogPath $catalogPath
    }

    [pscustomobject]@{
        InfFullPath                   = $infFullPath
        DriverFolder                  = $folderFullPath
        InfExists                     = $infExists
        DriverFolderExists            = $folderExists
        HasAdditionalFiles            = $hasAdditionalFiles
        PackageFileCount              = $fileCount
        MissingFiles                  = @($missingFiles | Select-Object -Unique)
        CatalogFiles                  = @($catalogFiles)
        CatalogPath                   = $catalogPath
        CatalogSignature              = $signature
        CatalogSignatureStatus        = if ($signature) { $signature.SignatureStatus } else { '' }
        CatalogSignatureStatusMessage = if ($signature) { $signature.SignatureStatusMessage } else { '' }
        CatalogSignatureValid         = if ($signature) { [bool]$signature.IsTrusted } else { $false }
        CatalogCertificateTrusted     = if ($signature) { [bool]$signature.IsTrusted } else { $false }
        CatalogSignerSubject          = if ($signature) { $signature.SignerSubject } else { '' }
        CatalogSignerIssuer           = if ($signature) { $signature.SignerIssuer } else { '' }
        CatalogSignerThumbprint       = if ($signature) { $signature.SignerThumbprint } else { '' }
        CatalogSignerNotBefore        = if ($signature) { $signature.SignerNotBefore } else { '' }
        CatalogSignerNotAfter         = if ($signature) { $signature.SignerNotAfter } else { '' }
        IsInstallable                 = ($infExists -and $folderExists -and $missingFiles.Count -eq 0 -and $hasAdditionalFiles -and ($catalogFiles.Count -eq 0 -or ($signature -and $signature.IsTrusted)))
    }
}

function Repair-MissingCatalogFilesFromBackup {
    param(
        [string]$InfPath,
        [string]$DriverFolder,
        [string]$BackupPath
    )

    if ([string]::IsNullOrWhiteSpace($BackupPath) -or -not (Test-Path -LiteralPath $BackupPath -PathType Container)) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($InfPath) -or -not (Test-Path -LiteralPath $InfPath -PathType Leaf)) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($DriverFolder) -or -not (Test-Path -LiteralPath $DriverFolder -PathType Container)) {
        return
    }

    foreach ($catalog in (Get-InfCatalogFiles -InfPath $InfPath)) {
        $expected = Join-Path $DriverFolder $catalog
        if (Test-Path -LiteralPath $expected -PathType Leaf) {
            continue
        }

        $found = Get-ChildItem -LiteralPath $BackupPath -Recurse -Filter $catalog -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            try {
                Copy-Item -LiteralPath $found.FullName -Destination $expected -Force:$false -ErrorAction Stop
                Write-DriverVaultLog ("Catalogo ausente reparado copiando {0} para {1}" -f $found.FullName, $expected) 'WARN'
            }
            catch {
                Write-DriverVaultLog ("Nao foi possivel reparar catalogo ausente {0}: {1}" -f $catalog, $_.Exception.Message) 'WARN'
            }
        }
    }
}

function New-RestorableDriverWithDiagnostics {
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
        [string]$CertificateRelativePath = ''
    )

    Repair-MissingCatalogFilesFromBackup -InfPath $InfPath -DriverFolder $DriverFolder -BackupPath $BackupPath
    $diagnostics = Get-RestorablePackageDiagnostics -InfPath $InfPath -DriverFolder $DriverFolder
    $relativeCatalogPath = ''
    if ($diagnostics.CatalogPath -and (Test-Path -LiteralPath $diagnostics.CatalogPath -PathType Leaf) -and (Test-Path -LiteralPath $BackupPath -PathType Container)) {
        try {
            $relativeCatalogPath = Get-RelativePathFromBase -BasePath $BackupPath -TargetPath $diagnostics.CatalogPath
        }
        catch {
            $relativeCatalogPath = ''
        }
    }

    $certificatePath = ''
    if (-not [string]::IsNullOrWhiteSpace($CertificateRelativePath)) {
        $candidateCertificate = Resolve-BackupRelativePath -BackupPath $BackupPath -RelativePath $CertificateRelativePath
        if ($candidateCertificate -and (Test-Path -LiteralPath $candidateCertificate -PathType Leaf)) {
            $certificatePath = (Resolve-Path -LiteralPath $candidateCertificate).Path
        }
    }

    $record = New-RestorableDriver `
        -Driver $Driver `
        -Fabricante $Fabricante `
        -Versao $Versao `
        -Arquitetura $Arquitetura `
        -InfPath $diagnostics.InfFullPath `
        -DriverFolder $diagnostics.DriverFolder `
        -BackupPath $BackupPath `
        -Source $Source `
        -RelativeInfPath $RelativeInfPath `
        -InfFile $InfFile `
        -InfExists $diagnostics.InfExists `
        -DriverFolderExists $diagnostics.DriverFolderExists `
        -HasAdditionalFiles $diagnostics.HasAdditionalFiles `
        -PackageFileCount $diagnostics.PackageFileCount `
        -MissingFiles $diagnostics.MissingFiles `
        -CatalogFiles $diagnostics.CatalogFiles `
        -CatalogPath $diagnostics.CatalogPath `
        -RelativeCatalogPath $relativeCatalogPath `
        -CatalogSignatureStatus $diagnostics.CatalogSignatureStatus `
        -CatalogSignatureStatusMessage $diagnostics.CatalogSignatureStatusMessage `
        -CatalogSignatureValid $diagnostics.CatalogSignatureValid `
        -CatalogCertificateTrusted $diagnostics.CatalogCertificateTrusted `
        -CatalogSignerSubject $diagnostics.CatalogSignerSubject `
        -CatalogSignerIssuer $diagnostics.CatalogSignerIssuer `
        -CatalogSignerThumbprint $diagnostics.CatalogSignerThumbprint `
        -CatalogSignerNotBefore $diagnostics.CatalogSignerNotBefore `
        -CatalogSignerNotAfter $diagnostics.CatalogSignerNotAfter `
        -CatalogCertificatePath $certificatePath `
        -CatalogCertificateRelativePath $CertificateRelativePath `
        -IsInstallable $diagnostics.IsInstallable `
        -IsValidated $true

    if (-not $record.InfExists) {
        $record.Status = 'INF ausente'
    }
    elseif ($record.MissingFiles.Count -gt 0) {
        $record.Status = 'Pacote incompleto'
        $record.Avisos = 'Arquivos referenciados ausentes: ' + ($record.MissingFiles -join ', ')
    }
    elseif (-not $record.HasAdditionalFiles) {
        $record.Status = 'Pacote incompleto'
        $record.Avisos = 'Pacote sem arquivos auxiliares alem do INF.'
    }
    elseif ($record.CatalogFiles.Count -gt 0 -and -not $record.CatalogSignatureValid) {
        if ($record.CatalogSignerThumbprint) {
            $record.Status = 'Certificado nao confiavel'
            $record.Avisos = 'Catalogo assinado, mas assinatura/certificado nao foi validado pelo Windows.'
        }
        else {
            $record.Status = 'Assinatura invalida'
            $record.Avisos = 'Catalogo sem assinatura valida.'
        }
    }
    return $record
}

function Get-InfMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InfPath
    )

    $name = [System.IO.Path]::GetFileNameWithoutExtension($InfPath)
    $version = 'N/D'
    $manufacturer = 'N/D'
    $architecture = $env:PROCESSOR_ARCHITECTURE
    $strings = @{}

    try {
        $lines = Get-Content -LiteralPath $InfPath -ErrorAction Stop
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\s*;' -or [string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            if ($trimmed -match '^\s*DriverVer\s*=\s*(.+)$') {
                $parts = $matches[1] -split ','
                if ($parts.Count -ge 2) {
                    $version = $parts[-1].Trim()
                }
                else {
                    $version = $matches[1].Trim()
                }
            }
            elseif ($trimmed -match '^\s*Provider\s*=\s*(.+)$') {
                $manufacturer = Resolve-InfStringValue -Value $matches[1].Trim() -Strings $strings
            }
            elseif ($trimmed -match '^\s*CatalogFile(\..+)?\s*=\s*(.+)$') {
                $catalogName = [System.IO.Path]::GetFileNameWithoutExtension($matches[2].Trim())
                if (-not [string]::IsNullOrWhiteSpace($catalogName)) {
                    $name = $catalogName
                }
            }
            elseif ($trimmed -match '^\s*([^=]+)\s*=\s*"(.*)"\s*$') {
                $strings[$matches[1].Trim()] = $matches[2].Trim()
            }
            elseif ($trimmed -match '^\s*([^=]+)\s*=\s*(.+)$') {
                $strings[$matches[1].Trim()] = $matches[2].Trim()
            }

            if ($trimmed -match 'NTamd64|x64') {
                $architecture = 'x64'
            }
            elseif ($trimmed -match 'NTx86|x86') {
                $architecture = 'x86'
            }
        }
    }
    catch {
        Write-DriverVaultLog ("Falha ao ler INF {0}: {1}" -f $InfPath, $_.Exception.Message) 'WARN'
    }

    [pscustomobject]@{
        Driver      = $name
        Fabricante  = $manufacturer
        Versao      = $version
        Arquitetura = $architecture
    }
}

function Resolve-InfStringValue {
    param(
        [string]$Value,
        [hashtable]$Strings
    )

    $text = $Value.Trim('"', ' ')
    if ($text -match '^%(.+)%$') {
        $key = $matches[1]
        if ($Strings.ContainsKey($key)) {
            return $Strings[$key]
        }
    }
    return $text
}
