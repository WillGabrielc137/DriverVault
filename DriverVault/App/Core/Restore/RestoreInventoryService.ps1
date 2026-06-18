# Modulo extraido de RestoreService.ps1.



function Get-InstalledPrinterDriversForRestore {
    $records = @()
    $printerDrivers = @()

    if (Get-Command -Name Get-PrinterDriver -ErrorAction SilentlyContinue) {
        $printerDrivers = @(Invoke-DriverQueryWithTimeout -Name 'Get-PrinterDriver para restauracao' -ScriptBlock {
                Get-PrinterDriver -ErrorAction Stop
            })
    }

    foreach ($driver in $printerDrivers) {
        $name = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('Name')) -Default 'Driver sem nome'
        $records += [pscustomobject]@{
            Driver           = $name
            Versao           = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('DriverVersion', 'MajorVersion', 'Version'))
            Fabricante       = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('Manufacturer', 'Provider'))
            Arquitetura      = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('PrinterEnvironment', 'Architecture')) -Default $env:PROCESSOR_ARCHITECTURE
            InfPath          = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('InfPath', 'InfName')) -Default ''
            Origem           = 'Get-PrinterDriver'
            ChaveNormalizada = Normalize-DriverName -Name $name
        }
    }

    if ($records.Count -eq 0) {
        $wmiDrivers = @(Invoke-DriverQueryWithTimeout -Name 'Win32_PrinterDriver para restauracao' -ScriptBlock {
                Get-CimInstance -ClassName Win32_PrinterDriver -ErrorAction Stop
            })
        foreach ($driver in $wmiDrivers) {
            $name = Get-WmiDriverDisplayName -Driver $driver
            $records += [pscustomobject]@{
                Driver           = $name
                Versao           = Get-WmiDriverVersion -Driver $driver
                Fabricante       = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('Manufacturer', 'Provider'))
                Arquitetura      = Get-WmiDriverArchitecture -Driver $driver
                InfPath          = ConvertTo-SafeText -Value (Get-ObjectPropertyValue -Object $driver -Names @('InfName', 'InfPath', 'DriverPath')) -Default ''
                Origem           = 'Win32_PrinterDriver'
                ChaveNormalizada = Normalize-DriverName -Name $name
            }
        }
    }

    return $records
}

function Find-InstalledDriverMatch {
    param(
        [Parameter(Mandatory = $true)]
        [object]$BackupDriver,
        [Parameter(Mandatory = $true)]
        [object[]]$InstalledDrivers
    )

    $backupName = ConvertTo-SafeText -Value $BackupDriver.Driver -Default ''
    $backupNorm = Normalize-DriverName -Name $backupName
    $backupVersion = ConvertTo-SafeText -Value $BackupDriver.Versao -Default ''
    $backupManufacturer = ConvertTo-SafeText -Value $BackupDriver.Fabricante -Default ''
    $backupInfLeaf = [System.IO.Path]::GetFileName($BackupDriver.InfPath)

    foreach ($installed in @($InstalledDrivers | Where-Object { $_ })) {
        $installedName = ConvertTo-SafeText -Value $installed.Driver -Default ''
        $installedNorm = Normalize-DriverName -Name $installedName
        $sameName = ($backupName.Trim() -ieq $installedName.Trim()) -or ($backupNorm -and $backupNorm -eq $installedNorm)
        $similarName = Test-DriverNamesSimilar -NameA $backupName -NameB $installedName
        $sameVersion = ($backupVersion -and $backupVersion -ne 'N/D' -and $backupVersion -eq (ConvertTo-SafeText -Value $installed.Versao -Default ''))
        $sameManufacturer = ($backupManufacturer -and $backupManufacturer -ne 'N/D' -and $backupManufacturer -eq (ConvertTo-SafeText -Value $installed.Fabricante -Default ''))
        $sameInf = ($backupInfLeaf -and $installed.InfPath -and ($backupInfLeaf -ieq [System.IO.Path]::GetFileName($installed.InfPath)))

        if ($sameName -or $sameInf -or ($similarName -and ($sameVersion -or $sameManufacturer))) {
            return $installed
        }
    }

    return $null
}
