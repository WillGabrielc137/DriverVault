function Get-DriverCatalogSignatureInfo {
    param(
        [string]$CatalogPath
    )

    $info = [pscustomobject]@{
        CatalogPath             = $CatalogPath
        Exists                  = $false
        SignatureStatus         = 'CatalogMissing'
        SignatureStatusMessage  = 'Catalogo ausente.'
        IsSigned                = $false
        IsTrusted               = $false
        IsUsableForInstall      = $false
        SignerSubject           = ''
        SignerIssuer            = ''
        SignerThumbprint        = ''
        SignerNotBefore         = ''
        SignerNotAfter          = ''
        TrustedPublisherPresent = $false
    }

    if ([string]::IsNullOrWhiteSpace($CatalogPath) -or -not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        return $info
    }

    $info.Exists = $true
    try {
        $signature = Get-AuthenticodeSignature -FilePath $CatalogPath -ErrorAction Stop
        $info.SignatureStatus = [string]$signature.Status
        $info.SignatureStatusMessage = ConvertTo-SafeText -Value $signature.StatusMessage -Default ''

        if ($signature.SignerCertificate) {
            $certificate = $signature.SignerCertificate
            $info.IsSigned = $true
            $info.SignerSubject = ConvertTo-SafeText -Value $certificate.Subject -Default ''
            $info.SignerIssuer = ConvertTo-SafeText -Value $certificate.Issuer -Default ''
            $info.SignerThumbprint = ConvertTo-SafeText -Value $certificate.Thumbprint -Default ''
            $info.SignerNotBefore = $certificate.NotBefore.ToString('yyyy-MM-dd HH:mm:ss')
            $info.SignerNotAfter = $certificate.NotAfter.ToString('yyyy-MM-dd HH:mm:ss')
            $info.TrustedPublisherPresent = Test-DriverCertificateInTrustedPublisher -Thumbprint $certificate.Thumbprint
        }

        $info.IsTrusted = ($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid)
        $info.IsUsableForInstall = $info.IsTrusted
    }
    catch {
        $info.SignatureStatus = 'SignatureReadError'
        $info.SignatureStatusMessage = $_.Exception.Message
        Write-DriverVaultLog ("Falha ao validar assinatura do catalogo {0}: {1}" -f $CatalogPath, $_.Exception.Message) 'WARN'
    }

    return $info
}

function Test-DriverCertificateInTrustedPublisher {
    param(
        [string]$Thumbprint
    )

    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        return $false
    }

    try {
        return (Test-Path -LiteralPath ("Cert:\LocalMachine\TrustedPublisher\{0}" -f $Thumbprint))
    }
    catch {
        return $false
    }
}

function Export-DriverCatalogCertificate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CatalogPath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    $signature = Get-DriverCatalogSignatureInfo -CatalogPath $CatalogPath
    if (-not $signature.IsSigned -or [string]::IsNullOrWhiteSpace($signature.SignerThumbprint)) {
        return [pscustomobject]@{ Exported = $false; CertificatePath = ''; Error = 'Catalogo sem certificado assinante.'; Signature = $signature }
    }

    try {
        if (-not (Test-Path -LiteralPath $DestinationFolder -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $DestinationFolder | Out-Null
        }

        $certPath = Join-Path $DestinationFolder ("{0}.cer" -f $signature.SignerThumbprint)
        $authSignature = Get-AuthenticodeSignature -FilePath $CatalogPath -ErrorAction Stop
        Export-Certificate -Cert $authSignature.SignerCertificate -FilePath $certPath -Force -ErrorAction Stop | Out-Null
        return [pscustomobject]@{ Exported = $true; CertificatePath = $certPath; Error = ''; Signature = $signature }
    }
    catch {
        Write-DriverVaultLog ("Falha ao exportar certificado do catalogo {0}: {1}" -f $CatalogPath, $_.Exception.Message) 'WARN'
        return [pscustomobject]@{ Exported = $false; CertificatePath = ''; Error = $_.Exception.Message; Signature = $signature }
    }
}

function Import-DriverCatalogCertificate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CertificatePath
    )

    if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
        throw "Certificado nao encontrado: $CertificatePath"
    }

    if (-not (Test-DriverVaultAdministrator)) {
        throw 'A importacao de certificado em LocalMachine\TrustedPublisher precisa de permissao de administrador.'
    }

    try {
        $result = Import-Certificate -FilePath $CertificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' -ErrorAction Stop
        return [pscustomobject]@{ Imported = $true; Thumbprint = $result.Thumbprint; Store = 'Cert:\LocalMachine\TrustedPublisher' }
    }
    catch {
        throw ("Falha ao importar certificado para TrustedPublisher: {0}" -f $_.Exception.Message)
    }
}

function Test-DriverSignatureCanPromptForTrust {
    param(
        [object]$SignatureInfo
    )

    if (-not $SignatureInfo) {
        return $false
    }

    return ($SignatureInfo.Exists -and $SignatureInfo.IsSigned -and -not $SignatureInfo.IsTrusted)
}
