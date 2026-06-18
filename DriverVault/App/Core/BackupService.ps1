# Carregador de compatibilidade. As funcoes foram separadas em modulos menores.
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'Backup\BackupPathService.ps1')
. (Join-Path $scriptDirectory 'PnP\PnPUtilService.ps1')
. (Join-Path $scriptDirectory 'PnP\DriverStoreService.ps1')
. (Join-Path $scriptDirectory 'Backup\BackupFileService.ps1')
. (Join-Path $scriptDirectory 'Backup\BackupJobService.ps1')
