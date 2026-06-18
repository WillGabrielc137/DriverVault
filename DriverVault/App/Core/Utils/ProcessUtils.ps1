# Modulo extraido de RestoreService.ps1.



function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        [string[]]$Arguments,
        [string]$WorkingDirectory = '',
        [int]$TimeoutSeconds = 120
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FileName
    $startInfo.Arguments = Join-ProcessArguments -Arguments $Arguments
    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    try {
        $oemEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        if ($startInfo.PSObject.Properties.Name -contains 'StandardOutputEncoding') {
            $startInfo.StandardOutputEncoding = $oemEncoding
        }
        if ($startInfo.PSObject.Properties.Name -contains 'StandardErrorEncoding') {
            $startInfo.StandardErrorEncoding = $oemEncoding
        }
    }
    catch {
        # Se o runtime nao expuser encoding de redirecionamento, segue com o padrao.
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $outputTask = $null
    $errorTask = $null

    try {
        [void]$process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            try {
                if ($outputTask) { [void]$outputTask.Wait(3000) }
                if ($errorTask) { [void]$errorTask.Wait(3000) }
            }
            catch {
                # Mesmo em timeout, retorna o que ja foi capturado.
            }
            return [pscustomobject]@{
                ExitCode = -1
                Output   = if ($outputTask -and $outputTask.IsCompleted) { $outputTask.Result } else { '' }
                Error    = "Tempo limite atingido apos $TimeoutSeconds segundos. " + $(if ($errorTask -and $errorTask.IsCompleted) { $errorTask.Result } else { '' })
            }
        }
        $process.WaitForExit()

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = if ($outputTask) { $outputTask.Result } else { '' }
            Error    = if ($errorTask) { $errorTask.Result } else { '' }
        }
    }
    finally {
        $process.Dispose()
    }
}

function Join-ProcessArguments {
    param(
        [string[]]$Arguments
    )

    $quoted = @()
    foreach ($argument in @($Arguments)) {
        if ($null -eq $argument) {
            continue
        }
        $looksLikeAbsoluteFilePath = ($argument -match '^[A-Za-z]:\\' -or $argument -match '^\\\\')
        if ($argument -match '[\s"]' -or $looksLikeAbsoluteFilePath) {
            $quoted += ('"{0}"' -f ($argument -replace '"', '\"'))
        }
        else {
            $quoted += $argument
        }
    }
    return ($quoted -join ' ')
}
