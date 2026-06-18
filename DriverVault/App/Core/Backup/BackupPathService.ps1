# Modulo extraido de BackupService.ps1.



function Resolve-BackupFolderName {
    param(
        [string]$RequestedName
    )

    if ([string]::IsNullOrWhiteSpace($RequestedName)) {
        return (ConvertTo-SafeFileName -Name ("SRV-{0}_{1}" -f (Get-DriverVaultServerName), (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')))
    }

    return (ConvertTo-SafeFileName -Name $RequestedName)
}

function Get-DriverVaultFolderCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,
        [string]$RequestedName
    )

    $safeName = Resolve-BackupFolderName -RequestedName $RequestedName
    [pscustomobject]@{
        Name   = $safeName
        Path   = Join-Path $DestinationRoot $safeName
        Exists = Test-Path -LiteralPath (Join-Path $DestinationRoot $safeName)
    }
}

function New-DriverVaultFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        New-Item -ItemType Directory -Force -Path $BackupPath | Out-Null
    }

    $driversRoot = Join-Path $BackupPath 'Drivers'
    if (-not (Test-Path -LiteralPath $driversRoot)) {
        New-Item -ItemType Directory -Force -Path $driversRoot | Out-Null
    }

    return $BackupPath
}

function Get-UniqueDirectoryPath {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $parent = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path
    for ($i = 2; $i -lt 1000; $i++) {
        $candidate = Join-Path $parent ("{0}_{1}" -f $leaf, $i)
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return (Join-Path $parent ("{0}_{1}" -f $leaf, (Get-Date -Format 'HHmmssfff')))
}
