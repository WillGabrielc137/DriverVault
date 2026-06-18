function Get-WmiDriverDisplayName {
    param(
        [object]$Driver
    )

    $name = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @('Name', 'DriverName')) -Default 'Driver sem nome'
    $parts = $name -split ','
    if ($parts.Count -ge 3) {
        return $parts[0].Trim()
    }
    return $name
}

function Get-WmiDriverArchitecture {
    param(
        [object]$Driver
    )

    $architecture = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @('PrinterEnvironment', 'SupportedPlatform', 'Architecture')) -Default ''
    if (-not [string]::IsNullOrWhiteSpace($architecture)) {
        return $architecture
    }

    $name = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @('Name')) -Default ''
    $parts = $name -split ','
    if ($parts.Count -ge 3) {
        return $parts[2].Trim()
    }
    return $env:PROCESSOR_ARCHITECTURE
}

function Get-WmiDriverVersion {
    param(
        [object]$Driver
    )

    $version = Get-ObjectPropertyValue -Object $Driver -Names @('DriverVersion', 'Version', 'MajorVersion')
    if ($null -ne $version) {
        return (ConvertTo-SafeText -Value $version)
    }

    $name = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $Driver -Names @('Name')) -Default ''
    $parts = $name -split ','
    if ($parts.Count -ge 2) {
        return $parts[1].Trim()
    }
    return 'N/D'
}

function Split-DriverPathValue {
    param(
        [object]$Value
    )

    $items = @()
    if ($null -eq $Value) {
        return $items
    }

    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
                $items += [string]$item
            }
        }
        return $items
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $items
    }

    foreach ($part in ($text -split '[;|]')) {
        if (-not [string]::IsNullOrWhiteSpace($part)) {
            $items += $part.Trim()
        }
    }
    return $items
}

function Set-DriverInfoProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [object]$Value
    )

    if ($Driver.PSObject.Properties[$Name]) {
        $Driver.PSObject.Properties[$Name].Value = $Value
    }
    else {
        Add-Member -InputObject $Driver -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function Test-DriverPathUnderDirectory {
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

function Get-PrinterDriverSearchBaseDirectories {
    param(
        [string[]]$AdditionalBaseDirectories = @()
    )

    $bases = @($AdditionalBaseDirectories | Where-Object { $_ })
    $spoolDrivers = Join-Path $env:windir 'System32\spool\drivers'
    $bases += @(
        (Join-Path $env:windir 'INF'),
        (Join-Path $env:windir 'System32'),
        $spoolDrivers
    )

    foreach ($environmentFolder in @('x64', 'W32X86', 'ARM64')) {
        foreach ($versionFolder in @('3', '4', 'PCC')) {
            $bases += (Join-Path $spoolDrivers (Join-Path $environmentFolder $versionFolder))
        }
    }

    return @($bases |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } |
        ForEach-Object { (Resolve-Path -LiteralPath $_).Path } |
        Select-Object -Unique)
}

function Resolve-DriverPath {
    param(
        [string]$RawPath,
        [string[]]$BaseDirectories
    )

    $resolved = @()
    if ([string]::IsNullOrWhiteSpace($RawPath)) {
        return $resolved
    }

    $clean = [Environment]::ExpandEnvironmentVariables($RawPath.Trim('"', ' '))
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $resolved
    }

    if ([System.IO.Path]::IsPathRooted($clean)) {
        if (Test-Path -LiteralPath $clean) {
            $resolved += (Resolve-Path -LiteralPath $clean).Path
        }
        return $resolved
    }

    $candidateBases = @(Get-PrinterDriverSearchBaseDirectories -AdditionalBaseDirectories $BaseDirectories)

    foreach ($base in ($candidateBases | Where-Object { $_ } | Select-Object -Unique)) {
        $candidate = Join-Path $base $clean
        if (Test-Path -LiteralPath $candidate) {
            $resolved += (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return ($resolved | Select-Object -Unique)
}

function Get-DriverFilesFromSourceObject {
    param(
        [object]$Driver
    )

    $pathProperties = @('InfPath', 'InfName', 'DriverPath', 'ConfigFile', 'DataFile', 'HelpFile', 'DependentFiles', 'Driver', 'Data File', 'Configuration File', 'Dependent Files')
    $rawValues = @()
    $baseDirectories = @()

    foreach ($propertyName in $pathProperties) {
        $value = Get-ObjectPropertyValue -Object $Driver -Names @($propertyName)
        foreach ($item in (Split-DriverPathValue -Value $value)) {
            $rawValues += $item
            $expanded = [Environment]::ExpandEnvironmentVariables($item.Trim('"', ' '))
            if ([System.IO.Path]::IsPathRooted($expanded) -and (Test-Path -LiteralPath $expanded)) {
                $resolved = (Resolve-Path -LiteralPath $expanded).Path
                if (Test-Path -LiteralPath $resolved -PathType Leaf) {
                    $baseDirectories += (Split-Path -Parent $resolved)
                }
                elseif (Test-Path -LiteralPath $resolved -PathType Container) {
                    $baseDirectories += $resolved
                }
            }
        }
    }

    $files = @()
    foreach ($raw in ($rawValues | Where-Object { $_ } | Select-Object -Unique)) {
        foreach ($resolved in (Resolve-DriverPath -RawPath $raw -BaseDirectories $baseDirectories)) {
            if (Test-Path -LiteralPath $resolved -PathType Leaf) {
                $files += $resolved
            }
            elseif (Test-Path -LiteralPath $resolved -PathType Container) {
                try {
                    $files += Get-ChildItem -LiteralPath $resolved -Recurse -File -ErrorAction Stop | ForEach-Object { $_.FullName }
                }
                catch {
                    Write-DriverVaultLog ("Falha ao listar pasta de driver {0}: {1}" -f $resolved, $_.Exception.Message) 'WARN'
                }
            }
        }
    }

    return ($files | Where-Object { $_ } | Select-Object -Unique)
}

function Invoke-DriverQueryWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 30
    )

    $job = $null
    try {
        $job = Start-Job -ScriptBlock $ScriptBlock -ErrorAction Stop
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if (-not $completed) {
            Write-DriverVaultLog ("Tempo limite atingido em {0} apos {1}s. A etapa sera ignorada para evitar travamento." -f $Name, $TimeoutSeconds) 'WARN'
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            return @()
        }

        return @(Receive-Job -Job $job -ErrorAction Stop)
    }
    catch {
        Write-DriverVaultLog ("Falha na consulta {0}: {1}" -f $Name, $_.Exception.Message) 'WARN'
        return @()
    }
    finally {
        if ($job) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-PrinterDriverRegistryRecords {
    $records = @()
    $environments = @(
        [pscustomobject]@{ Name = 'Windows x64'; Architecture = 'Windows x64' },
        [pscustomobject]@{ Name = 'Windows NT x86'; Architecture = 'Windows x86' },
        [pscustomobject]@{ Name = 'Windows ARM64'; Architecture = 'Windows ARM64' }
    )

    foreach ($environment in $environments) {
        foreach ($versionKey in @('Version-3', 'Version-4')) {
            $path = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\$($environment.Name)\Drivers\$versionKey"
            if (-not (Test-Path -LiteralPath $path)) {
                continue
            }

            foreach ($key in @(Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue)) {
                try {
                    $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                    $driverName = ConvertTo-SafeText -Value $key.PSChildName -Default 'Driver sem nome'
                    $infPath = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $props -Names @('InfPath')) -Default ''
                    $baseDirectories = @()
                    if ($infPath -and [System.IO.Path]::IsPathRooted($infPath) -and (Test-Path -LiteralPath $infPath)) {
                        $resolvedInf = (Resolve-Path -LiteralPath $infPath).Path
                        $baseDirectories += (Split-Path -Parent $resolvedInf)
                    }

                    $sourceFiles = @()
                    foreach ($propertyName in @('InfPath', 'Driver', 'Data File', 'Configuration File', 'Dependent Files')) {
                        $value = Get-ObjectPropertyValue -Object $props -Names @($propertyName)
                        foreach ($item in (Split-DriverPathValue -Value $value)) {
                            $sourceFiles += @(Resolve-DriverPath -RawPath $item -BaseDirectories $baseDirectories)
                        }
                    }
                    $sourceFiles = @($sourceFiles | Where-Object { $_ } | Select-Object -Unique)

                    $spoolRoot = Join-Path $env:windir 'System32\spool\drivers'
                    $driverStoreRoot = Join-Path $env:windir 'System32\DriverStore\FileRepository'
                    $spoolFiles = @($sourceFiles | Where-Object { Test-DriverPathUnderDirectory -Path $_ -ParentPath $spoolRoot })
                    $driverStoreFiles = @($sourceFiles | Where-Object { Test-DriverPathUnderDirectory -Path $_ -ParentPath $driverStoreRoot })

                    $record = [pscustomobject]@{
                        Driver           = $driverName
                        Fabricante       = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $props -Names @('Manufacturer', 'Provider')) -Default 'N/D'
                        Provider         = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $props -Names @('Provider', 'Manufacturer')) -Default ''
                        Versao           = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $props -Names @('DriverVersion', 'Version')) -Default 'N/D'
                        Arquitetura      = $environment.Architecture
                        VersionKey       = $versionKey
                        RegistryPath     = $key.PSPath
                        InfPath          = $infPath
                        DriverFile       = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $props -Names @('Driver')) -Default ''
                        DataFile         = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $props -Names @('Data File')) -Default ''
                        ConfigFile       = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $props -Names @('Configuration File')) -Default ''
                        DependentFiles   = @(Split-DriverPathValue -Value (Get-ObjectPropertyValue -Object $props -Names @('Dependent Files')))
                        SourceFiles      = $sourceFiles
                        SpoolFiles       = $spoolFiles
                        DriverStoreFiles = $driverStoreFiles
                    }

                    Write-DriverVaultLog ("Registro de driver de impressora: Nome={0}; Ambiente={1}; Chave={2}; Fabricante={3}; InfPath={4}; Driver={5}; DataFile={6}; ConfigFile={7}; Arquivos={8}; Spooler={9}; DriverStore={10}" -f $record.Driver, $record.Arquitetura, $record.VersionKey, $record.Fabricante, $record.InfPath, $record.DriverFile, $record.DataFile, $record.ConfigFile, @($record.SourceFiles).Count, @($record.SpoolFiles).Count, @($record.DriverStoreFiles).Count)
                    $records += $record
                }
                catch {
                    Write-DriverVaultLog ("Falha ao ler registro de driver de impressora {0}: {1}" -f $key.PSPath, $_.Exception.Message) 'WARN'
                }
            }
        }
    }

    return $records
}

function Update-DriverInfoFromRegistryRecord {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver,
        [Parameter(Mandatory = $true)]
        [object]$RegistryRecord
    )

    $Driver.CaminhosArquivos = @($Driver.CaminhosArquivos + @($RegistryRecord.SourceFiles) | Where-Object { $_ } | Select-Object -Unique)
    if ($Driver.Fabricante -eq 'N/D' -and $RegistryRecord.Fabricante -ne 'N/D') {
        $Driver.Fabricante = $RegistryRecord.Fabricante
    }
    if ($Driver.Origem -notmatch 'Registro de impressao') {
        $Driver.Origem = ($Driver.Origem + '; Registro de impressao ' + $RegistryRecord.VersionKey).Trim(';', ' ')
    }

    Set-DriverInfoProperty -Driver $Driver -Name 'SourceRegistryPath' -Value $RegistryRecord.RegistryPath
    Set-DriverInfoProperty -Driver $Driver -Name 'SourceSpoolFiles' -Value @($RegistryRecord.SpoolFiles)
    Set-DriverInfoProperty -Driver $Driver -Name 'SourceDriverStoreFiles' -Value @($RegistryRecord.DriverStoreFiles)
    if ($RegistryRecord.Provider -and -not $Driver.DriverPackageProvider) {
        $Driver.DriverPackageProvider = $RegistryRecord.Provider
    }

    if ($RegistryRecord.InfPath) {
        Set-DriverInfoProperty -Driver $Driver -Name 'SourceInfPath' -Value $RegistryRecord.InfPath
        $infLeaf = [System.IO.Path]::GetFileName($RegistryRecord.InfPath)
        if ($infLeaf -match '^oem\d+\.inf$') {
            $Driver.PublishedName = $infLeaf
        }
        elseif ([System.IO.Path]::GetExtension($infLeaf) -ieq '.inf') {
            $Driver.OriginalInfName = $infLeaf
        }
    }
}

function Get-PrinterDriverInventory {
    Write-DriverVaultLog 'Iniciando coleta de drivers de impressora.'
    $records = @()
    $wmiDrivers = @()

    $wmiDrivers = @(Invoke-DriverQueryWithTimeout -Name 'Get-CimInstance Win32_PrinterDriver' -ScriptBlock {
            Get-CimInstance -ClassName Win32_PrinterDriver -ErrorAction Stop
        })
    if ($wmiDrivers.Count -gt 0) {
        Write-DriverVaultLog ("Drivers obtidos via CIM/WMI: {0}" -f $wmiDrivers.Count)
    }
    else {
        $wmiDrivers = @(Invoke-DriverQueryWithTimeout -Name 'Get-WmiObject Win32_PrinterDriver' -ScriptBlock {
                Get-WmiObject -Class Win32_PrinterDriver -ErrorAction Stop
            })
        Write-DriverVaultLog ("Drivers obtidos via Get-WmiObject: {0}" -f $wmiDrivers.Count)
    }

    $getPrinterDriver = Get-Command -Name Get-PrinterDriver -ErrorAction SilentlyContinue
    if ($getPrinterDriver) {
        $printerDrivers = @(Invoke-DriverQueryWithTimeout -Name 'Get-PrinterDriver' -ScriptBlock {
                Get-PrinterDriver -ErrorAction Stop
            })
        if ($printerDrivers.Count -gt 0) {
            Write-DriverVaultLog ("Drivers obtidos via Get-PrinterDriver: {0}" -f $printerDrivers.Count)
            foreach ($driver in $printerDrivers) {
                $records += New-DriverInfo `
                    -Driver (ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('Name')) -Default 'Driver sem nome') `
                    -Fabricante (ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('Manufacturer', 'Provider'))) `
                    -Versao (ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('DriverVersion', 'MajorVersion', 'Version'))) `
                    -Arquitetura (ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('PrinterEnvironment', 'Architecture')) -Default $env:PROCESSOR_ARCHITECTURE) `
                    -CaminhosArquivos @(Get-DriverFilesFromSourceObject -Driver $driver) `
                    -Origem 'Get-PrinterDriver'
            }
        }
    }
    else {
        Write-DriverVaultLog 'Get-PrinterDriver nao esta disponivel. Usando WMI/CIM quando possivel.' 'WARN'
    }

    if ($records.Count -eq 0 -and $wmiDrivers.Count -gt 0) {
        foreach ($driver in $wmiDrivers) {
            $records += New-DriverInfo `
                -Driver (Get-WmiDriverDisplayName -Driver $driver) `
                -Fabricante (ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('Manufacturer', 'Provider'))) `
                -Versao (Get-WmiDriverVersion -Driver $driver) `
                -Arquitetura (Get-WmiDriverArchitecture -Driver $driver) `
                -CaminhosArquivos @(Get-DriverFilesFromSourceObject -Driver $driver) `
                -Origem 'Win32_PrinterDriver'
        }
    }
    elseif ($records.Count -gt 0 -and $wmiDrivers.Count -gt 0) {
        foreach ($record in $records) {
            $matches = @($wmiDrivers | Where-Object {
                    Test-DriverNamesSimilar -NameA $record.Driver -NameB (Get-WmiDriverDisplayName -Driver $_)
                })
            foreach ($match in $matches) {
                $extraFiles = @(Get-DriverFilesFromSourceObject -Driver $match)
                if ($extraFiles.Count -gt 0) {
                    $record.CaminhosArquivos = @($record.CaminhosArquivos + $extraFiles | Where-Object { $_ } | Select-Object -Unique)
                }
                if ($record.Fabricante -eq 'N/D') {
                    $record.Fabricante = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $match -Names @('Manufacturer', 'Provider'))
                }
            }
        }
    }

    $registryRecords = @(Get-PrinterDriverRegistryRecords)
    Write-DriverVaultLog ("Drivers obtidos via registro de impressao: {0}" -f $registryRecords.Count)
    foreach ($registryRecord in $registryRecords) {
        $matches = @($records | Where-Object {
                Test-DriverNamesSimilar -NameA $_.Driver -NameB $registryRecord.Driver
            })

        if ($matches.Count -gt 0) {
            foreach ($match in $matches) {
                Update-DriverInfoFromRegistryRecord -Driver $match -RegistryRecord $registryRecord
            }
            continue
        }

        $newRecord = New-DriverInfo `
            -Driver $registryRecord.Driver `
            -Fabricante $registryRecord.Fabricante `
            -Versao $registryRecord.Versao `
            -Arquitetura $registryRecord.Arquitetura `
            -CaminhosArquivos @($registryRecord.SourceFiles) `
            -Origem ("Registro de impressao {0}" -f $registryRecord.VersionKey)
        Update-DriverInfoFromRegistryRecord -Driver $newRecord -RegistryRecord $registryRecord
        $records += $newRecord
    }

    $unique = @{}
    foreach ($record in $records) {
        $key = '{0}|{1}|{2}' -f $record.ChaveNormalizada, $record.Versao, $record.Arquitetura
        if (-not $unique.ContainsKey($key)) {
            $unique[$key] = $record
        }
        else {
            $existing = $unique[$key]
            $existing.CaminhosArquivos = @($existing.CaminhosArquivos + $record.CaminhosArquivos | Where-Object { $_ } | Select-Object -Unique)
            $existing.SourceSpoolFiles = @($existing.SourceSpoolFiles + $record.SourceSpoolFiles | Where-Object { $_ } | Select-Object -Unique)
            $existing.SourceDriverStoreFiles = @($existing.SourceDriverStoreFiles + $record.SourceDriverStoreFiles | Where-Object { $_ } | Select-Object -Unique)
            foreach ($propertyName in @('SourceInfPath', 'SourceRegistryPath', 'PublishedName', 'OriginalInfName', 'DriverPackageProvider')) {
                if ([string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -Object $existing -Names @($propertyName)))) {
                    $value = Get-ObjectPropertyValue -Object $record -Names @($propertyName)
                    if ($null -ne $value) {
                        Set-DriverInfoProperty -Driver $existing -Name $propertyName -Value $value
                    }
                }
            }
            if ($existing.Origem -notmatch [regex]::Escape($record.Origem)) {
                $existing.Origem = ($existing.Origem + '; ' + $record.Origem)
            }
        }
    }

    $result = @($unique.Values | Sort-Object Driver, Versao, Arquitetura)
    Write-DriverVaultLog ("Total de drivers consolidados: {0}" -f $result.Count)
    foreach ($driver in $result) {
        Write-DriverVaultLog ("Driver encontrado: {0} | Fabricante: {1} | Versao: {2} | Arquitetura: {3} | Arquivos: {4}" -f $driver.Driver, $driver.Fabricante, $driver.Versao, $driver.Arquitetura, $driver.CaminhosArquivos.Count)
    }
    return $result
}
