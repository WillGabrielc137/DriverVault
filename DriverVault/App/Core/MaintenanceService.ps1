function Assert-ManagedProjectFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedPath
    )

    $targetFull = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
    $expectedFull = [System.IO.Path]::GetFullPath($ExpectedPath).TrimEnd('\')
    if (-not $targetFull.Equals($expectedFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Operacao bloqueada. Pasta fora do local permitido: $TargetPath"
    }
}

function Clear-ManagedFolderFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedPath,
        [Parameter(Mandatory = $true)]
        [string]$ContentName
    )

    Assert-ManagedProjectFolder -TargetPath $FolderPath -ExpectedPath $ExpectedPath

    if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $FolderPath | Out-Null
    }

    $folderFull = (Resolve-Path -LiteralPath $FolderPath).Path.TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $folderFull -File -Recurse -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) {
        return [pscustomobject]@{
            Success = $true
            DeletedCount = 0
            Errors = @()
            Message = "Nao ha $ContentName para apagar."
        }
    }

    $deleted = 0
    $errors = @()
    foreach ($file in $files) {
        $fileFull = [System.IO.Path]::GetFullPath($file.FullName)
        if (-not $fileFull.StartsWith($folderFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $errors += "Arquivo fora da pasta permitida ignorado: $fileFull"
            continue
        }

        try {
            Remove-Item -LiteralPath $fileFull -Force -ErrorAction Stop
            $deleted++
        } catch {
            $errors += ("{0}: {1}" -f $fileFull, $_.Exception.Message)
        }
    }

    [pscustomobject]@{
        Success = ($errors.Count -eq 0)
        DeletedCount = $deleted
        Errors = @($errors)
        Message = if ($errors.Count -eq 0) {
            "$deleted arquivo(s) de $ContentName apagado(s)."
        } else {
            "$deleted arquivo(s) de $ContentName apagado(s), com $($errors.Count) erro(s)."
        }
    }
}

function Clear-DriverVaultLogs {
    $state = Get-DriverVaultState
    Write-DriverVaultLog 'Limpeza de logs solicitada pelo usuario.'
    $result = Clear-ManagedFolderFiles -FolderPath $state.LogRoot -ExpectedPath $state.LogRoot -ContentName 'logs'
    Write-DriverVaultLog ("Resultado da limpeza de logs: {0}" -f $result.Message)
    return $result
}

function Clear-DriverVaultReports {
    $state = Get-DriverVaultState
    $result = Clear-ManagedFolderFiles -FolderPath $state.ReportRoot -ExpectedPath $state.ReportRoot -ContentName 'relatorios'
    return $result
}
