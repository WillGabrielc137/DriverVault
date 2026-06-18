function New-BackupResult {
    param(
        [string]$BackupPath,
        [object[]]$Drivers,
        [object[]]$Duplicados,
        [object]$ReportPath,
        [string[]]$Errors
    )

    [pscustomobject]@{
        BackupPath  = $BackupPath
        Drivers     = @($Drivers)
        Duplicados  = @($Duplicados)
        ReportPath  = $ReportPath
        Errors      = @($Errors)
        CompletedAt = Get-Date
    }
}
