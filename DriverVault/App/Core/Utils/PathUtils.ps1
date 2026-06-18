# Modulo extraido de RestoreService.ps1.



function Get-RelativePathFromBase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $baseFull = (Resolve-Path -LiteralPath $BasePath).Path
    $targetFull = (Resolve-Path -LiteralPath $TargetPath).Path
    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Resolve-BackupRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return ''
    }

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        return $RelativePath
    }

    return (Join-Path $BackupPath $RelativePath)
}

function Resolve-FullPathIfExists {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return [System.IO.Path]::GetFullPath($Path)
}
