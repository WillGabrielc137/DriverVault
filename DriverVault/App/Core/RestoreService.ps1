# Carregador de compatibilidade. As funcoes foram separadas em modulos menores.
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'Utils\PathUtils.ps1')
. (Join-Path $scriptDirectory 'Utils\ProcessUtils.ps1')
. (Join-Path $scriptDirectory 'Validation\InfValidationService.ps1')
. (Join-Path $scriptDirectory 'ManifestService.ps1')
. (Join-Path $scriptDirectory 'Restore\RestoreInventoryService.ps1')
. (Join-Path $scriptDirectory 'Restore\RestoreInstallService.ps1')
