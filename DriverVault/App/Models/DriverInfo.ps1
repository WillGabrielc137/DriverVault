function New-DriverInfo {
    param(
        [string]$Driver,
        [string]$Fabricante,
        [string]$Versao,
        [string]$Arquitetura,
        [string[]]$CaminhosArquivos,
        [string]$Origem
    )

    $driverName = ConvertTo-SafeText -Value $Driver -Default 'Driver sem nome'
    [pscustomobject]@{
        Driver                         = $driverName
        Fabricante                     = ConvertTo-SafeText -Value $Fabricante
        Versao                         = ConvertTo-SafeText -Value $Versao
        Arquitetura                    = ConvertTo-SafeText -Value $Arquitetura -Default $env:PROCESSOR_ARCHITECTURE
        CaminhosArquivos               = @($CaminhosArquivos | Where-Object { $_ } | Select-Object -Unique)
        DataColeta                     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Servidor                       = Get-DriverVaultServerName
        Origem                         = $Origem
        Status                         = 'Encontrado'
        SelectedForBackup              = $false
        BackupStatus                   = 'NotStarted'
        IsInstallable                  = $false
        ValidationMessages             = @()
        ChaveNormalizada               = Normalize-DriverName -Name $driverName
        CaminhoBackup                  = ''
        SourceInfPath                  = ''
        SourceRegistryPath             = ''
        SourceSpoolFiles               = @()
        SourceDriverStoreFiles         = @()
        RelativeInfPath                = ''
        BackupDriverFolder             = ''
        ArquivosCopiados               = 0
        PrimaryInfPath                 = ''
        OriginalInfName                = ''
        PublishedName                  = ''
        DriverPackageProvider          = ''
        DriverPackageClass             = ''
        DriverPackageVersion           = ''
        CatalogFiles                   = @()
        CatalogPath                    = ''
        RelativeCatalogPath            = ''
        CatalogSignatureStatus         = ''
        CatalogSignatureStatusMessage  = ''
        CatalogSignatureValid          = $false
        CatalogCertificateTrusted      = $false
        CatalogSignerSubject           = ''
        CatalogSignerIssuer            = ''
        CatalogSignerThumbprint        = ''
        CatalogSignerNotBefore         = ''
        CatalogSignerNotAfter          = ''
        CatalogCertificatePath         = ''
        CatalogCertificateRelativePath = ''
        DriverStoreExported            = $false
        PackageExported                = $false
        PackageExportSource            = ''
        PackageValidation              = ''
        InstallerPath                  = ''
        RelativeInstallerPath          = ''
        Avisos                         = ''
        Erros                          = ''
    }
}
