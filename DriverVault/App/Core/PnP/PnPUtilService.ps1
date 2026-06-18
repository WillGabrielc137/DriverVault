# Modulo extraido de BackupService.ps1.



function Get-PnPUtilPath {
    $pnputil = Join-Path $env:windir 'System32\pnputil.exe'
    if (Test-Path -LiteralPath $pnputil -PathType Leaf) {
        return $pnputil
    }
    return 'pnputil.exe'
}

function Normalize-PnPUtilLabel {
    param(
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Label)) {
        return ''
    }

    $text = Remove-DriverNameDiacritics -Text $Label
    $text = $text.ToLowerInvariant()
    $text = $text -replace '[^a-z0-9]+', ' '
    return $text.Trim()
}

function ConvertFrom-PnPUtilDriverOutput {
    param(
        [string]$Text
    )

    $packages = @()
    $current = [ordered]@{}
    $text = (($Text) -replace "`r", '')

    foreach ($line in ($text -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.Count -gt 0) {
                $packages += New-PnPUtilPackageObject -Values $current
                $current = [ordered]@{}
            }
            continue
        }

        if ($line -match '^\s*([^:]+):\s*(.+?)\s*$') {
            $label = Normalize-PnPUtilLabel -Label $matches[1]
            $value = $matches[2].Trim()
            if ($label -match 'published name|nome publicado') {
                $current.PublishedName = $value
            }
            elseif ($label -match 'original name|nome original') {
                $current.OriginalName = $value
            }
            elseif ($label -match 'provider name|nome do provedor|provedor') {
                $current.Provider = $value
            }
            elseif ($label -match 'class name|nome da classe|classe') {
                $current.ClassName = $value
            }
            elseif ($label -match 'driver version|versao do driver|data e versao') {
                $current.DriverVersion = $value
            }
            elseif ($label -match 'signer name|nome do signatario|assinante|signatario') {
                $current.SignerName = $value
            }
        }
    }

    if ($current.Count -gt 0) {
        $packages += New-PnPUtilPackageObject -Values $current
    }

    return $packages
}

function Get-PnPUtilDriverPackages {
    $state = Get-DriverVaultState
    if ($state.Contains('PnPUtilDriverPackages')) {
        return @($state['PnPUtilDriverPackages'])
    }

    $packages = @()
    try {
        $attempts = @(
            [pscustomobject]@{ Arguments = @('/enum-drivers', '/class', 'Printer'); Label = 'pnputil /enum-drivers /class Printer' },
            [pscustomobject]@{ Arguments = @('/enum-drivers'); Label = 'pnputil /enum-drivers' }
        )

        foreach ($attempt in $attempts) {
            $result = Invoke-ProcessWithTimeout -FileName (Get-PnPUtilPath) -Arguments $attempt.Arguments -TimeoutSeconds 45
            if ($result.ExitCode -ne 0) {
                Write-DriverVaultLog ("{0} falhou ou atingiu timeout. Codigo={1}; Saida={2}; Erro={3}" -f $attempt.Label, $result.ExitCode, (($result.Output -replace '\r?\n', ' ').Trim()), (($result.Error -replace '\r?\n', ' ').Trim())) 'WARN'
                continue
            }

            $packages = @(ConvertFrom-PnPUtilDriverOutput -Text ($result.Output + [Environment]::NewLine + $result.Error))
            Write-DriverVaultLog ("Pacotes enumerados com {0}: {1}" -f $attempt.Label, $packages.Count)
            if ($packages.Count -gt 0) {
                break
            }
        }
    }
    catch {
        Write-DriverVaultLog ("Falha ao enumerar pacotes com pnputil: {0}" -f $_.Exception.Message) 'WARN'
    }

    $state['PnPUtilDriverPackages'] = $packages
    return $packages
}

function New-PnPUtilPackageObject {
    param(
        [object]$Values
    )

    [pscustomobject]@{
        PublishedName = ConvertTo-SafeText -Value $Values['PublishedName'] -Default ''
        OriginalName  = ConvertTo-SafeText -Value $Values['OriginalName'] -Default ''
        Provider      = ConvertTo-SafeText -Value $Values['Provider'] -Default ''
        ClassName     = ConvertTo-SafeText -Value $Values['ClassName'] -Default ''
        DriverVersion = ConvertTo-SafeText -Value $Values['DriverVersion'] -Default ''
        SignerName    = ConvertTo-SafeText -Value $Values['SignerName'] -Default ''
    }
}

function Export-DriverPackageWithPnPUtil {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Package,
        [Parameter(Mandatory = $true)]
        [string]$TargetFolder
    )

    $resultObject = [pscustomobject]@{
        Exported              = $false
        FilesCopied           = 0
        ExportedInfPath       = ''
        ExportedPackageFolder = ''
        Output                = ''
        Error                 = ''
    }

    if (-not $Package.PublishedName) {
        $resultObject.Error = 'Pacote sem PublishedName.'
        return $resultObject
    }

    if (-not (Test-Path -LiteralPath $TargetFolder -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $TargetFolder | Out-Null
    }

    $exportRoot = Join-Path $TargetFolder ('__pnputil_export_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $exportRoot | Out-Null

    try {
        $result = Invoke-ProcessWithTimeout -FileName (Get-PnPUtilPath) -Arguments @('/export-driver', $Package.PublishedName, $exportRoot) -WorkingDirectory $TargetFolder -TimeoutSeconds 180
        $resultObject.Output = $result.Output
        $resultObject.Error = $result.Error

        if ($result.ExitCode -ne 0) {
            Write-DriverVaultLog ("pnputil /export-driver falhou para {0}: {1} {2}" -f $Package.PublishedName, $result.Output, $result.Error) 'WARN'
            return $resultObject
        }

        $exportedInf = Find-ExportedPackageInf -ExportRoot $exportRoot -Package $Package
        if (-not $exportedInf) {
            $resultObject.Error = 'pnputil exportou o pacote, mas nenhum INF foi localizado no destino temporario.'
            Write-DriverVaultLog $resultObject.Error 'WARN'
            return $resultObject
        }

        $packageFolder = Split-Path -Parent $exportedInf
        $resultObject.ExportedInfPath = $exportedInf
        $resultObject.ExportedPackageFolder = $packageFolder
        $resultObject.FilesCopied = Copy-DirectoryContentsSafe -SourceFolder $packageFolder -DestinationFolder $TargetFolder
        $resultObject.Exported = $true
        return $resultObject
    }
    catch {
        $resultObject.Error = $_.Exception.Message
        Write-DriverVaultLog ("Falha ao exportar pacote {0}: {1}" -f $Package.PublishedName, $_.Exception.Message) 'WARN'
        return $resultObject
    }
    finally {
        try {
            if (Test-Path -LiteralPath $exportRoot) {
                $resolvedExport = (Resolve-Path -LiteralPath $exportRoot).Path
                $resolvedTarget = (Resolve-Path -LiteralPath $TargetFolder).Path
                if ($resolvedExport.StartsWith($resolvedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Remove-Item -LiteralPath $resolvedExport -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-DriverVaultLog ("Nao foi possivel remover pasta temporaria do pnputil: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
}

function Find-ExportedPackageInf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExportRoot,
        [Parameter(Mandatory = $true)]
        [object]$Package
    )

    $infFiles = @(Get-ChildItem -LiteralPath $ExportRoot -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue)
    if ($infFiles.Count -eq 0) {
        return ''
    }

    if ($Package.OriginalName) {
        $match = $infFiles | Where-Object { $_.Name -ieq $Package.OriginalName } | Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    if ($Package.PublishedName) {
        $match = $infFiles | Where-Object { $_.Name -ieq $Package.PublishedName } | Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    return $infFiles[0].FullName
}
