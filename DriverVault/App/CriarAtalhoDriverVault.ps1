param(
    [string]$ShortcutPath = ([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'DriverVault.lnk'))
)

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $projectRoot 'App\Start-DriverVault.vbs'

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Launcher nao encontrado: $scriptPath"
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = 'wscript.exe'
$shortcut.Arguments = "`"$scriptPath`""
$shortcut.WorkingDirectory = $projectRoot
$shortcut.IconLocation = 'wscript.exe,0'
$shortcut.Description = 'DriverVault - backup e restauracao de drivers de impressora'
$shortcut.Save()

Write-Host "Atalho criado em: $ShortcutPath"
