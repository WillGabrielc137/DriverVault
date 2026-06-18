# Modulo extraido de BackupService.ps1.



function Get-InfNamesFromSourceFiles {
    param(
        [string[]]$SourceFiles
    )

    return @($SourceFiles |
        Where-Object { $_ -and ([System.IO.Path]::GetExtension($_) -ieq '.inf') } |
        ForEach-Object { [System.IO.Path]::GetFileName($_) } |
        Where-Object { $_ } |
        Select-Object -Unique)
}

function Get-SourceFileStemTokens {
    param(
        [string[]]$SourceFiles
    )

    return @($SourceFiles |
        Where-Object { $_ } |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) } |
        Where-Object { $_ -and $_.Length -gt 2 } |
        Select-Object -Unique)
}

function Get-DriverStoreInfPathsByName {
    param(
        [string]$InfName
    )

    $matches = @()
    if ([string]::IsNullOrWhiteSpace($InfName)) {
        return $matches
    }

    $driverStore = Join-Path $env:windir 'System32\DriverStore\FileRepository'
    if (-not (Test-Path -LiteralPath $driverStore -PathType Container)) {
        return $matches
    }

    try {
        $candidateFolders = @(Get-ChildItem -LiteralPath $driverStore -Directory -Filter ("{0}*" -f $InfName) -ErrorAction SilentlyContinue)
        foreach ($folder in $candidateFolders) {
            $match = Get-ChildItem -LiteralPath $folder.FullName -Recurse -Filter $InfName -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) {
                $matches += $match.FullName
            }
        }

        if ($matches.Count -eq 0) {
            $matches += @(Get-ChildItem -LiteralPath $driverStore -Recurse -Filter $InfName -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }
    catch {
        Write-DriverVaultLog ("Falha ao procurar INF no DriverStore ({0}): {1}" -f $InfName, $_.Exception.Message) 'WARN'
    }

    return @($matches | Where-Object { $_ } | Select-Object -Unique)
}

function Test-PnPUtilPackageInfMentionsDriver {
    param(
        [object]$Package,
        [object]$Driver
    )

    $driverName = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @('Driver')) -Default ''
    $driverNorm = Normalize-DriverName -Name $driverName
    if ([string]::IsNullOrWhiteSpace($driverNorm)) {
        return $false
    }

    $tokens = @($driverNorm -split '\s+' | Where-Object { $_.Length -gt 2 } | Select-Object -Unique)
    $infNames = @()
    foreach ($name in @($Package.OriginalName, $Package.PublishedName)) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $infNames += $name
        }
    }

    foreach ($infName in @($infNames | Select-Object -Unique)) {
        foreach ($infPath in (Get-DriverStoreInfPathsByName -InfName $infName)) {
            try {
                $content = Get-Content -LiteralPath $infPath -Raw -ErrorAction Stop
                $contentNorm = Normalize-DriverName -Name $content
                if ($contentNorm.Contains($driverNorm)) {
                    return $true
                }

                $hits = 0
                foreach ($token in $tokens) {
                    if ($contentNorm -match [regex]::Escape($token)) {
                        $hits++
                    }
                }
                if ($tokens.Count -gt 0 -and $hits -ge [Math]::Min(3, $tokens.Count)) {
                    return $true
                }
            }
            catch {
                Write-DriverVaultLog ("Falha ao analisar INF do DriverStore {0}: {1}" -f $infPath, $_.Exception.Message) 'WARN'
            }
        }
    }

    return $false
}

function Find-PnPUtilPackageForDriver {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver,
        [string[]]$SourceFiles
    )

    $infNames = @(Get-InfNamesFromSourceFiles -SourceFiles $SourceFiles)
    foreach ($propertyName in @('SourceInfPath', 'OriginalInfName', 'PublishedName')) {
        $value = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @($propertyName)) -Default ''
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $leaf = [System.IO.Path]::GetFileName($value)
            if ([System.IO.Path]::GetExtension($leaf) -ieq '.inf') {
                $infNames += $leaf
            }
        }
    }
    $infNames = @($infNames | Where-Object { $_ } | Select-Object -Unique)
    $sourceStems = @(Get-SourceFileStemTokens -SourceFiles $SourceFiles)
    $sourceStems += @($infNames | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) } | Where-Object { $_ })
    $sourceStems = @($sourceStems | Where-Object { $_ } | Select-Object -Unique)
    $driverManufacturer = Normalize-DriverName -Name (ConvertTo-SafeText -Value $Driver.Fabricante -Default '')
    $driverNameNorm = Normalize-DriverName -Name (ConvertTo-SafeText -Value $Driver.Driver -Default '')
    $packages = @(Get-PnPUtilDriverPackages)
    $scored = @()

    foreach ($package in $packages) {
        $score = 0
        $reasons = @()
        foreach ($infName in $infNames) {
            if ($package.PublishedName -and $package.PublishedName -ieq $infName) {
                $score += 120
                $reasons += "PublishedName=$infName"
            }
            if ($package.OriginalName -and $package.OriginalName -ieq $infName) {
                $score += 100
                $reasons += "OriginalName=$infName"
            }
        }

        $packageInfStems = @()
        foreach ($name in @($package.PublishedName, $package.OriginalName)) {
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $packageInfStems += [System.IO.Path]::GetFileNameWithoutExtension($name)
            }
        }
        foreach ($stem in $sourceStems) {
            if ($packageInfStems -contains $stem) {
                $score += 80
                $reasons += "base INF=$stem"
                break
            }
        }

        $providerNorm = Normalize-DriverName -Name $package.Provider
        if ($driverManufacturer -and $providerNorm -and ($providerNorm.Contains($driverManufacturer) -or $driverManufacturer.Contains($providerNorm))) {
            $score += 25
            $reasons += 'fabricante'
        }
        elseif ($driverNameNorm -and $providerNorm -and $driverNameNorm.Contains($providerNorm)) {
            $score += 20
            $reasons += 'nome/provedor'
        }

        $classNorm = Normalize-PnPUtilLabel -Label $package.ClassName
        if ($classNorm -match 'printer|print|impress|4d36e979 e325 11ce bfc1 08002be10318') {
            $score += 10
            $reasons += 'classe impressora'
        }

        if ($score -ge 20 -and $score -lt 100 -and (Test-PnPUtilPackageInfMentionsDriver -Package $package -Driver $Driver)) {
            $score += 80
            $reasons += 'INF contem nome do driver'
        }

        if ($score -gt 0) {
            $scored += [pscustomobject]@{ Package = $package; Score = $score; Reasons = ($reasons -join ', ') }
        }
    }

    $best = $scored | Sort-Object Score -Descending | Select-Object -First 1
    if ($best -and $best.Score -ge 100) {
        Write-DriverVaultLog ("Pacote pnputil associado a {0}: {1} ({2}); score={3}; motivo={4}" -f $Driver.Driver, $best.Package.PublishedName, $best.Package.OriginalName, $best.Score, $best.Reasons)
        return $best.Package
    }

    $providerPrinterMatches = @($scored | Where-Object { $_.Score -ge 35 } | Sort-Object Score -Descending)
    if ($providerPrinterMatches.Count -eq 1) {
        $match = $providerPrinterMatches[0]
        Write-DriverVaultLog ("Pacote pnputil associado por provedor/classe a {0}: {1} ({2}); score={3}; motivo={4}" -f $Driver.Driver, $match.Package.PublishedName, $match.Package.OriginalName, $match.Score, $match.Reasons) 'WARN'
        return $match.Package
    }

    if ($scored.Count -gt 0) {
        $topCandidates = @($scored | Sort-Object Score -Descending | Select-Object -First 5 | ForEach-Object {
                "{0} ({1}) score={2} motivo={3}" -f $_.Package.PublishedName, $_.Package.OriginalName, $_.Score, $_.Reasons
            })
        Write-DriverVaultLog ("Nenhum pacote pnputil atingiu confianca para {0}. INF candidatos: {1}; stems: {2}; melhores candidatos: {3}" -f $Driver.Driver, ($infNames -join ', '), ($sourceStems -join ', '), ($topCandidates -join ' | ')) 'WARN'
    }
    else {
        Write-DriverVaultLog ("Nenhum pacote pnputil pontuou para {0}. Fabricante={1}; SourceInfPath={2}; INF candidatos={3}; stems={4}; arquivos fonte={5}" -f $Driver.Driver, $Driver.Fabricante, (ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @('SourceInfPath')) -Default ''), ($infNames -join ', '), ($sourceStems -join ', '), @($SourceFiles).Count) 'WARN'
    }

    return $null
}

function Test-IsUnderPath {
    param(
        [string]$Path,
        [string]$ParentPath
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($ParentPath)) {
        return $false
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
        $fullParent = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\')
        return $fullPath.StartsWith($fullParent, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Get-DriverStorePackageFolders {
    param(
        [string[]]$SourceFiles
    )

    $folders = @()
    $driverStore = Join-Path $env:windir 'System32\DriverStore\FileRepository'
    if (-not (Test-Path -LiteralPath $driverStore -PathType Container)) {
        return $folders
    }

    foreach ($infPath in @($SourceFiles | Where-Object { $_ -and ([System.IO.Path]::GetExtension($_) -ieq '.inf') })) {
        $infName = [System.IO.Path]::GetFileName($infPath)
        if ([string]::IsNullOrWhiteSpace($infName)) {
            continue
        }

        try {
            foreach ($match in (Get-DriverStoreInfPathsByName -InfName $infName)) {
                $folders += (Split-Path -Parent $match)
            }
        }
        catch {
            Write-DriverVaultLog ("Falha ao procurar pacote no DriverStore para {0}: {1}" -f $infName, $_.Exception.Message) 'WARN'
        }
    }

    return @($folders | Where-Object { $_ } | Select-Object -Unique)
}

function Get-AdditionalPackageFolders {
    param(
        [string[]]$SourceFiles
    )

    $folders = @()
    $windowsInf = Join-Path $env:windir 'INF'
    $spoolDrivers = Join-Path $env:windir 'System32\spool\drivers'
    $driverStore = Join-Path $env:windir 'System32\DriverStore\FileRepository'

    foreach ($infPath in @($SourceFiles | Where-Object { $_ -and ([System.IO.Path]::GetExtension($_) -ieq '.inf') })) {
        if (-not (Test-Path -LiteralPath $infPath -PathType Leaf)) {
            continue
        }
        $parent = Split-Path -Parent (Resolve-Path -LiteralPath $infPath).Path
        if (Test-IsUnderPath -Path $parent -ParentPath $driverStore) {
            $folders += $parent
        }
        elseif (-not (Test-IsUnderPath -Path $parent -ParentPath $windowsInf) -and -not (Test-IsUnderPath -Path $parent -ParentPath $spoolDrivers) -and -not (Test-IsUnderPath -Path $parent -ParentPath $env:windir)) {
            $folders += $parent
        }
    }

    $folders += @(Get-DriverStorePackageFolders -SourceFiles $SourceFiles)
    return @($folders | Where-Object { $_ } | Select-Object -Unique)
}
