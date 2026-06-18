# Carregador de compatibilidade. As funcoes foram separadas em modulos menores.
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'UiState.ps1')
. (Join-Path $scriptDirectory 'Panels\BackupPanel.ps1')
. (Join-Path $scriptDirectory 'Panels\RestorePanel.ps1')
. (Join-Path $scriptDirectory 'MainForm.ps1')
