function New-RestorableDriver {
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
        [bool]$InfExists = $false,
        [bool]$DriverFolderExists = $false,
        [bool]$HasAdditionalFiles = $false,
        [int]$PackageFileCount = 0,
        [string[]]$MissingFiles = @(),
        [string[]]$CatalogFiles = @(),
        [string]$CatalogPath = '',
        [string]$RelativeCatalogPath = '',
        [string]$CatalogSignatureStatus = '',
        [string]$CatalogSignatureStatusMessage = '',
        [bool]$CatalogSignatureValid = $false,
        [bool]$CatalogCertificateTrusted = $false,
        [string]$CatalogSignerSubject = '',
        [string]$CatalogSignerIssuer = '',
        [string]$CatalogSignerThumbprint = '',
        [string]$CatalogSignerNotBefore = '',
        [string]$CatalogSignerNotAfter = '',
        [string]$CatalogCertificatePath = '',
        [string]$CatalogCertificateRelativePath = '',
        [bool]$IsInstallable = $false,
        [bool]$IsValidated = $false
    )

    if ([string]::IsNullOrWhiteSpace($InfFile) -and -not [string]::IsNullOrWhiteSpace($InfPath)) {
        $InfFile = [System.IO.Path]::GetFileName($InfPath)
    }

    [pscustomobject]@{
        Selected                       = $false
        Driver                         = ConvertTo-SafeText -Value $Driver -Default 'Driver sem nome'
        Fabricante                     = ConvertTo-SafeText -Value $Fabricante
        Versao                         = ConvertTo-SafeText -Value $Versao
        Arquitetura                    = ConvertTo-SafeText -Value $Arquitetura -Default $env:PROCESSOR_ARCHITECTURE
        InfPath                        = $InfPath
        RelativeInfPath                = $RelativeInfPath
        InfFile                        = $InfFile
        DriverFolder                   = $DriverFolder
        BackupPath                     = $BackupPath
        Source                         = $Source
        InfExists                      = $InfExists
        DriverFolderExists             = $DriverFolderExists
        HasAdditionalFiles             = $HasAdditionalFiles
        PackageFileCount               = $PackageFileCount
        MissingFiles                   = @($MissingFiles)
        CatalogFiles                   = @($CatalogFiles)
        CatalogPath                    = $CatalogPath
        RelativeCatalogPath            = $RelativeCatalogPath
        CatalogSignatureStatus         = $CatalogSignatureStatus
        CatalogSignatureStatusMessage  = $CatalogSignatureStatusMessage
        CatalogSignatureValid          = $CatalogSignatureValid
        CatalogCertificateTrusted      = $CatalogCertificateTrusted
        CatalogSignerSubject           = $CatalogSignerSubject
        CatalogSignerIssuer            = $CatalogSignerIssuer
        CatalogSignerThumbprint        = $CatalogSignerThumbprint
        CatalogSignerNotBefore         = $CatalogSignerNotBefore
        CatalogSignerNotAfter          = $CatalogSignerNotAfter
        CatalogCertificatePath         = $CatalogCertificatePath
        CatalogCertificateRelativePath = $CatalogCertificateRelativePath
        IsInstallable                  = $IsInstallable
        IsValidated                    = $IsValidated
        Status                         = 'Disponivel'
        Avisos                         = ''
        Erros                          = ''
    }
}
