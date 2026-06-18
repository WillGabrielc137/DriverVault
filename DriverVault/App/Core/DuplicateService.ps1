function Remove-DriverNameDiacritics {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }
    return $builder.ToString().Normalize([System.Text.NormalizationForm]::FormC)
}

function Normalize-DriverName {
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }

    $text = (Remove-DriverNameDiacritics -Text $Name).ToLowerInvariant()
    $text = $text -replace '\b(versao|version|vers|ver|rev|revision)\s*\.?\s*\d+([._-]\d+)*\b', ' '
    $text = $text -replace '\bv\s*\d+([._-]\d+)*\b', ' '
    $text = $text -replace '\b\d+(\.\d+){1,4}\b', ' '
    $text = $text -replace '\b(driver|drivers)\b', ' '
    $text = $text -replace '[^a-z0-9]+', ' '
    $text = $text -replace '\s+', ' '
    return $text.Trim()
}

function Get-DriverNameDistance {
    param(
        [string]$A,
        [string]$B
    )

    if ($null -eq $A) { $A = '' }
    if ($null -eq $B) { $B = '' }
    if ($A -eq $B) { return 0 }

    $lenA = $A.Length
    $lenB = $B.Length
    if ($lenA -eq 0) { return $lenB }
    if ($lenB -eq 0) { return $lenA }

    $previous = New-Object 'int[]' ($lenB + 1)
    $current = New-Object 'int[]' ($lenB + 1)
    for ($j = 0; $j -le $lenB; $j++) {
        $previous[$j] = $j
    }

    for ($i = 1; $i -le $lenA; $i++) {
        $current[0] = $i
        for ($j = 1; $j -le $lenB; $j++) {
            $cost = 1
            if ($A[$i - 1] -eq $B[$j - 1]) {
                $cost = 0
            }
            $delete = $previous[$j] + 1
            $insert = $current[$j - 1] + 1
            $substitute = $previous[$j - 1] + $cost
            $current[$j] = [Math]::Min([Math]::Min($delete, $insert), $substitute)
        }

        $temp = $previous
        $previous = $current
        $current = $temp
    }

    return $previous[$lenB]
}

function Get-DriverNameSimilarity {
    param(
        [string]$A,
        [string]$B
    )

    if ($null -eq $A) { $A = '' }
    if ($null -eq $B) { $B = '' }
    $max = [Math]::Max($A.Length, $B.Length)
    if ($max -eq 0) {
        return 1
    }
    $distance = Get-DriverNameDistance -A $A -B $B
    return (1 - ($distance / $max))
}

function Test-DriverNamesSimilar {
    param(
        [string]$NameA,
        [string]$NameB
    )

    $a = Normalize-DriverName -Name $NameA
    $b = Normalize-DriverName -Name $NameB
    if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) {
        return $false
    }
    if ($a -eq $b) {
        return $true
    }
    if (($a.Length -ge 8 -and $b.Contains($a)) -or ($b.Length -ge 8 -and $a.Contains($b))) {
        return $true
    }
    return ((Get-DriverNameSimilarity -A $a -B $b) -ge 0.88)
}

function Compare-DriverDuplicate {
    param(
        [object]$Reference,
        [object]$Candidate
    )

    if ($null -eq $Reference -or $null -eq $Candidate) {
        return $null
    }

    $nameA = ConvertTo-SafeText -Value $Reference.Driver -Default ''
    $nameB = ConvertTo-SafeText -Value $Candidate.Driver -Default ''
    $normA = Normalize-DriverName -Name $nameA
    $normB = Normalize-DriverName -Name $nameB
    if ([string]::IsNullOrWhiteSpace($normA) -or [string]::IsNullOrWhiteSpace($normB)) {
        return $null
    }

    $sameRawName = ($nameA.Trim() -ieq $nameB.Trim())
    $sameNormalizedName = ($normA -eq $normB)
    $similarity = Get-DriverNameSimilarity -A $normA -B $normB
    $contains = (($normA.Length -ge 8 -and $normB.Contains($normA)) -or ($normB.Length -ge 8 -and $normA.Contains($normB)))
    if (-not ($sameRawName -or $sameNormalizedName -or $contains -or $similarity -ge 0.88)) {
        return $null
    }

    $sameVersion = ((ConvertTo-SafeText -Value $Reference.Versao -Default '') -eq (ConvertTo-SafeText -Value $Candidate.Versao -Default ''))
    $sameManufacturer = ($Reference.Fabricante -and $Candidate.Fabricante -and $Reference.Fabricante -ne 'N/D' -and $Candidate.Fabricante -ne 'N/D' -and $Reference.Fabricante -eq $Candidate.Fabricante)
    $sameArchitecture = ($Reference.Arquitetura -and $Candidate.Arquitetura -and $Reference.Arquitetura -eq $Candidate.Arquitetura)

    $reason = 'Nome igual ou muito parecido'
    if ($sameRawName -and -not $sameVersion) {
        $reason = 'Mesmo nome com versao diferente'
    }
    elseif ($sameRawName -and $sameVersion) {
        $reason = 'Mesmo nome e mesma versao'
    }
    elseif ($sameManufacturer -and $sameArchitecture) {
        $reason = 'Nome parecido, mesmo fabricante e mesma arquitetura'
    }
    elseif ($sameArchitecture) {
        $reason = 'Nome parecido e mesma arquitetura'
    }
    elseif ($sameManufacturer) {
        $reason = 'Nome parecido e mesmo fabricante'
    }

    return New-DuplicateDriver -Referencia $Reference -Novo $Candidate -Similaridade $similarity -Motivo $reason
}

function Find-DriverDuplicates {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Drivers
    )

    $result = @()
    $seen = @{}
    $items = @($Drivers | Where-Object { $_ })
    for ($i = 0; $i -lt $items.Count; $i++) {
        for ($j = $i + 1; $j -lt $items.Count; $j++) {
            $duplicate = Compare-DriverDuplicate -Reference $items[$i] -Candidate $items[$j]
            if ($duplicate) {
                $keyParts = @(
                    (Normalize-DriverName -Name $duplicate.DriverReferencia),
                    $duplicate.VersaoReferencia,
                    (Normalize-DriverName -Name $duplicate.NovoDriver),
                    $duplicate.NovaVersao,
                    $duplicate.OrigemReferencia,
                    $duplicate.OrigemNovo
                )
                $key = ($keyParts -join '|')
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $result += $duplicate
                }
            }
        }
    }
    return $result
}

function Find-DuplicatesForDriver {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver,
        [object[]]$ExistingDrivers
    )

    $result = @()
    foreach ($existing in @($ExistingDrivers | Where-Object { $_ })) {
        $duplicate = Compare-DriverDuplicate -Reference $existing -Candidate $Driver
        if ($duplicate) {
            $result += $duplicate
        }
    }
    return $result
}

function ConvertTo-ExistingDriverRecord {
    param(
        [object]$Item,
        [string]$SourcePath
    )

    $driver = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Item -Names @('Driver', 'NomeDriver', 'Name')) -Default 'Driver sem nome'
    [pscustomobject]@{
        Driver           = $driver
        Fabricante       = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Item -Names @('Fabricante', 'Manufacturer'))
        Versao           = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Item -Names @('Versao', 'Version', 'DriverVersion'))
        Arquitetura      = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Item -Names @('Arquitetura', 'Architecture', 'PrinterEnvironment'))
        DataColeta       = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Item -Names @('DataColeta', 'CollectedAt'))
        Servidor         = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Item -Names @('Servidor', 'Server'))
        Origem           = 'Manifesto existente'
        OrigemManifesto  = $SourcePath
        CaminhoBackup    = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Item -Names @('CaminhoBackup', 'BackupPath')) -Default ''
        ChaveNormalizada = Normalize-DriverName -Name $driver
        Status           = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Item -Names @('Status')) -Default ''
    }
}

function Get-ExistingManifestRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $records = @()
    if (-not (Test-Path -LiteralPath $RepositoryRoot)) {
        return $records
    }

    $manifestFiles = @()
    try {
        $manifestFiles = @(Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -ErrorAction SilentlyContinue | Where-Object {
                -not $_.PSIsContainer -and ($_.Name -eq 'manifesto_drivers.json' -or $_.Name -eq 'manifesto_drivers.csv')
            })
    }
    catch {
        Write-DriverVaultLog ("Falha ao procurar manifestos antigos em {0}: {1}" -f $RepositoryRoot, $_.Exception.Message) 'WARN'
    }

    foreach ($file in $manifestFiles) {
        try {
            if ($file.Extension -ieq '.json') {
                $data = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                foreach ($item in @($data)) {
                    $records += ConvertTo-ExistingDriverRecord -Item $item -SourcePath $file.FullName
                }
            }
            elseif ($file.Extension -ieq '.csv') {
                foreach ($item in @(Import-Csv -LiteralPath $file.FullName -ErrorAction Stop)) {
                    $records += ConvertTo-ExistingDriverRecord -Item $item -SourcePath $file.FullName
                }
            }
        }
        catch {
            Write-DriverVaultLog ("Falha ao ler manifesto antigo {0}: {1}" -f $file.FullName, $_.Exception.Message) 'WARN'
        }
    }

    return $records
}

function Get-RepositoryFolderDriverRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $records = @()
    if (-not (Test-Path -LiteralPath $RepositoryRoot)) {
        return $records
    }

    try {
        $driversFolders = @(Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Drivers' })
        foreach ($driversFolder in $driversFolders) {
            foreach ($child in @(Get-ChildItem -LiteralPath $driversFolder.FullName -Directory -ErrorAction SilentlyContinue)) {
                if ($child.Name -eq 'Duplicados') {
                    foreach ($dupChild in @(Get-ChildItem -LiteralPath $child.FullName -Directory -ErrorAction SilentlyContinue)) {
                        $records += New-RepositoryFolderRecord -Folder $dupChild
                    }
                }
                else {
                    $records += New-RepositoryFolderRecord -Folder $child
                }
            }
        }
    }
    catch {
        Write-DriverVaultLog ("Falha ao varrer pastas existentes em {0}: {1}" -f $RepositoryRoot, $_.Exception.Message) 'WARN'
    }

    return $records
}

function New-RepositoryFolderRecord {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo]$Folder
    )

    $display = ($Folder.Name -replace '_', ' ')
    [pscustomobject]@{
        Driver           = $display
        Fabricante       = 'N/D'
        Versao           = 'N/D'
        Arquitetura      = 'N/D'
        DataColeta       = ''
        Servidor         = ''
        Origem           = 'Pasta existente'
        CaminhoBackup    = $Folder.FullName
        ChaveNormalizada = Normalize-DriverName -Name $display
        Status           = ''
    }
}

function Get-ExistingRepositoryRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $records = @()
    $records += @(Get-ExistingManifestRecords -RepositoryRoot $RepositoryRoot)
    $records += @(Get-RepositoryFolderDriverRecords -RepositoryRoot $RepositoryRoot)
    return $records
}
