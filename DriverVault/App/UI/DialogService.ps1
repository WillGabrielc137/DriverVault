function Invoke-DuplicateDecisionDialog {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Driver,
        [Parameter(Mandatory = $true)]
        [object]$Duplicado
    )

    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Possivel driver repetido'
        $form.StartPosition = 'CenterParent'
        $form.Size = New-Object System.Drawing.Size(700, 360)
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.BackColor = Get-ThemeColor '#111827'
        $form.ForeColor = Get-ThemeColor '#E5E7EB'
        $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $form.Tag = 'Keep'

        $title = New-DarkLabel -Text 'ATENCAO: Driver possivelmente repetido encontrado.' -X 18 -Y 18 -Width 640 -Height 28
        $title.ForeColor = Get-ThemeColor '#FBBF24'
        $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
        $form.Controls.Add($title)

        $message = New-Object System.Windows.Forms.TextBox
        $message.Multiline = $true
        $message.ReadOnly = $true
        $message.BorderStyle = 'FixedSingle'
        $message.BackColor = Get-ThemeColor '#1F2937'
        $message.ForeColor = Get-ThemeColor '#F9FAFB'
        $message.Location = New-Object System.Drawing.Point(20, 58)
        $message.Size = New-Object System.Drawing.Size(640, 175)
        $message.Text = @"
Driver encontrado: $($Driver.Driver)
Versao encontrada: $($Driver.Versao)
Fabricante: $($Driver.Fabricante)
Arquitetura: $($Driver.Arquitetura)

Possivel repeticao com: $($Duplicado.DriverReferencia)
Versao existente: $($Duplicado.VersaoReferencia)
Nova versao encontrada: $($Driver.Versao)
Motivo: $($Duplicado.Motivo)
"@
        $form.Controls.Add($message)

        $btnKeep = New-DarkButton -Text 'Manter duas versoes' -X 20 -Y 255 -Width 190 -Height 38 -Color '#2563EB'
        $btnKeep.Add_Click({ $form.Tag = 'Keep'; $form.Close() })
        $form.Controls.Add($btnKeep)

        $btnSkip = New-DarkButton -Text 'Ignorar nova copia' -X 235 -Y 255 -Width 190 -Height 38 -Color '#374151'
        $btnSkip.Add_Click({ $form.Tag = 'Skip'; $form.Close() })
        $form.Controls.Add($btnSkip)

        $btnSeparate = New-DarkButton -Text 'Salvar em pasta separada' -X 450 -Y 255 -Width 210 -Height 38 -Color '#059669'
        $btnSeparate.Add_Click({ $form.Tag = 'Separate'; $form.Close() })
        $form.Controls.Add($btnSeparate)

        [void]$form.ShowDialog()
        return [string]$form.Tag
    }
    catch {
        Write-DriverVaultLog ("Falha ao exibir dialogo de duplicidade: {0}" -f $_.Exception.Message) 'WARN'
        return 'Keep'
    }
}

function Invoke-BackupFolderConflictDialog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Pasta de backup ja existe'
    $form.StartPosition = 'CenterParent'
    $form.Size = New-Object System.Drawing.Size(650, 260)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = Get-ThemeColor '#111827'
    $form.ForeColor = Get-ThemeColor '#E5E7EB'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Tag = 'Cancel'

    $title = New-DarkLabel -Text 'A pasta informada ja existe.' -X 18 -Y 18 -Width 590 -Height 28
    $title.ForeColor = Get-ThemeColor '#FBBF24'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($title)

    $message = New-Object System.Windows.Forms.TextBox
    $message.Multiline = $true
    $message.ReadOnly = $true
    $message.BorderStyle = 'FixedSingle'
    $message.BackColor = Get-ThemeColor '#1F2937'
    $message.ForeColor = Get-ThemeColor '#F9FAFB'
    $message.Location = New-Object System.Drawing.Point(20, 58)
    $message.Size = New-Object System.Drawing.Size(590, 82)
    $message.Text = "Caminho:`r`n$BackupPath`r`n`r`nEscolha como deseja continuar."
    $form.Controls.Add($message)

    $btnUse = New-DarkButton -Text 'Usar existente' -X 20 -Y 160 -Width 170 -Height 36 -Color '#2563EB'
    $btnUse.Add_Click({ $form.Tag = 'UseExisting'; $form.Close() })
    $form.Controls.Add($btnUse)

    $btnRename = New-DarkButton -Text 'Escolher outro nome' -X 220 -Y 160 -Width 190 -Height 36 -Color '#374151'
    $btnRename.Add_Click({ $form.Tag = 'ChooseAnother'; $form.Close() })
    $form.Controls.Add($btnRename)

    $btnCancel = New-DarkButton -Text 'Cancelar' -X 440 -Y 160 -Width 170 -Height 36 -Color '#7F1D1D'
    $btnCancel.Add_Click({ $form.Tag = 'Cancel'; $form.Close() })
    $form.Controls.Add($btnCancel)

    [void]$form.ShowDialog()
    return [string]$form.Tag
}

function Invoke-BackupFolderNameDialog {
    param(
        [string]$CurrentName
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Nome da pasta do backup'
    $form.StartPosition = 'CenterParent'
    $form.Size = New-Object System.Drawing.Size(560, 190)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = Get-ThemeColor '#111827'
    $form.ForeColor = Get-ThemeColor '#E5E7EB'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Tag = $null

    $label = New-DarkLabel -Text 'Informe outro nome para a pasta do backup:' -X 18 -Y 18 -Width 500
    $form.Controls.Add($label)

    $textBox = New-DarkTextBox -X 20 -Y 48 -Width 500 -Text $CurrentName
    $form.Controls.Add($textBox)

    $btnOk = New-DarkButton -Text 'OK' -X 250 -Y 95 -Width 120 -Height 34 -Color '#2563EB'
    $btnOk.Add_Click({ $form.Tag = $textBox.Text; $form.Close() })
    $form.Controls.Add($btnOk)

    $btnCancel = New-DarkButton -Text 'Cancelar' -X 395 -Y 95 -Width 125 -Height 34 -Color '#374151'
    $btnCancel.Add_Click({ $form.Tag = $null; $form.Close() })
    $form.Controls.Add($btnCancel)

    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel
    [void]$form.ShowDialog()
    return $form.Tag
}

function Resolve-BackupFolderSelection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,
        [string]$BackupFolderName,
        [object]$BackupNameTextBox
    )

    if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
        [System.Windows.Forms.MessageBox]::Show('Selecione uma pasta mae de destino valida.', 'Pasta invalida', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $null
    }

    $name = $BackupFolderName
    while ($true) {
        $candidate = Get-DriverVaultFolderCandidate -DestinationRoot $DestinationRoot -RequestedName $name
        if ($BackupNameTextBox) {
            $BackupNameTextBox.Text = $candidate.Name
        }

        if (-not $candidate.Exists) {
            return $candidate
        }

        $choice = Invoke-BackupFolderConflictDialog -BackupPath $candidate.Path
        if ($choice -eq 'UseExisting') {
            return $candidate
        }
        if ($choice -eq 'Cancel') {
            return $null
        }

        $newName = Invoke-BackupFolderNameDialog -CurrentName $candidate.Name
        if ($null -eq $newName) {
            return $null
        }
        $name = $newName
    }
}

function Invoke-RestoreConflictDialog {
    param(
        [Parameter(Mandatory = $true)]
        [object]$BackupDriver,
        [Parameter(Mandatory = $true)]
        [object]$InstalledDriver
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Driver ja instalado'
    $form.StartPosition = 'CenterParent'
    $form.Size = New-Object System.Drawing.Size(700, 360)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = Get-ThemeColor '#111827'
    $form.ForeColor = Get-ThemeColor '#E5E7EB'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Tag = 'Skip'

    $title = New-DarkLabel -Text 'Este driver ja existe nesta maquina/servidor.' -X 18 -Y 18 -Width 640 -Height 28
    $title.ForeColor = Get-ThemeColor '#FBBF24'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($title)

    $message = New-Object System.Windows.Forms.TextBox
    $message.Multiline = $true
    $message.ReadOnly = $true
    $message.BorderStyle = 'FixedSingle'
    $message.BackColor = Get-ThemeColor '#1F2937'
    $message.ForeColor = Get-ThemeColor '#F9FAFB'
    $message.Location = New-Object System.Drawing.Point(20, 58)
    $message.Size = New-Object System.Drawing.Size(640, 175)
    $message.Text = @"
Driver no backup: $($BackupDriver.Driver)
Versao do backup: $($BackupDriver.Versao)
Fabricante do backup: $($BackupDriver.Fabricante)
INF do backup: $($BackupDriver.InfPath)

Driver instalado: $($InstalledDriver.Driver)
Versao instalada: $($InstalledDriver.Versao)
Fabricante instalado: $($InstalledDriver.Fabricante)
Origem instalada: $($InstalledDriver.Origem)
"@
    $form.Controls.Add($message)

    $btnReplace = New-DarkButton -Text 'Substituir' -X 20 -Y 255 -Width 190 -Height 38 -Color '#B45309'
    $btnReplace.Add_Click({ $form.Tag = 'Replace'; $form.Close() })
    $form.Controls.Add($btnReplace)

    $btnSkip = New-DarkButton -Text 'Ignorar / manter' -X 235 -Y 255 -Width 190 -Height 38 -Color '#374151'
    $btnSkip.Add_Click({ $form.Tag = 'Skip'; $form.Close() })
    $form.Controls.Add($btnSkip)

    $btnCancel = New-DarkButton -Text 'Cancelar' -X 450 -Y 255 -Width 190 -Height 38 -Color '#7F1D1D'
    $btnCancel.Add_Click({ $form.Tag = 'Cancel'; $form.Close() })
    $form.Controls.Add($btnCancel)

    [void]$form.ShowDialog()
    return [string]$form.Tag
}

function Invoke-CertificateTrustDialog {
    param(
        [Parameter(Mandatory = $true)]
        [object]$BackupDriver,
        [Parameter(Mandatory = $true)]
        [object]$Diagnostics,
        [string]$CertificatePath = ''
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Certificado do driver'
    $form.StartPosition = 'CenterParent'
    $form.Size = New-Object System.Drawing.Size(760, 430)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = Get-ThemeColor '#111827'
    $form.ForeColor = Get-ThemeColor '#E5E7EB'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Tag = 'Cancel'

    $title = New-DarkLabel -Text 'O certificado do catalogo nao e confiavel nesta maquina.' -X 18 -Y 18 -Width 700 -Height 28
    $title.ForeColor = Get-ThemeColor '#FBBF24'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($title)

    $message = New-Object System.Windows.Forms.TextBox
    $message.Multiline = $true
    $message.ReadOnly = $true
    $message.BorderStyle = 'FixedSingle'
    $message.BackColor = Get-ThemeColor '#1F2937'
    $message.ForeColor = Get-ThemeColor '#F9FAFB'
    $message.Location = New-Object System.Drawing.Point(20, 58)
    $message.Size = New-Object System.Drawing.Size(700, 245)
    $message.Text = @"
Driver: $($BackupDriver.Driver)
INF: $($BackupDriver.InfPath)
Catalogo: $($Diagnostics.CatalogPath)

Status da assinatura: $($Diagnostics.CatalogSignatureStatus)
Mensagem: $($Diagnostics.CatalogSignatureStatusMessage)
Thumbprint: $($Diagnostics.CatalogSignerThumbprint)
Emissor: $($Diagnostics.CatalogSignerIssuer)
Validade: $($Diagnostics.CatalogSignerNotBefore) ate $($Diagnostics.CatalogSignerNotAfter)

Certificado exportado do pacote: $CertificatePath

Deseja importar o certificado do driver para Editores Confiaveis antes de instalar?
"@
    $form.Controls.Add($message)

    $btnImport = New-DarkButton -Text 'Importar e continuar' -X 20 -Y 325 -Width 210 -Height 38 -Color '#059669'
    $btnImport.Add_Click({ $form.Tag = 'Import'; $form.Close() })
    $form.Controls.Add($btnImport)

    $btnContinue = New-DarkButton -Text 'Continuar sem importar' -X 255 -Y 325 -Width 220 -Height 38 -Color '#B45309'
    $btnContinue.Add_Click({ $form.Tag = 'Continue'; $form.Close() })
    $form.Controls.Add($btnContinue)

    $btnCancel = New-DarkButton -Text 'Cancelar' -X 500 -Y 325 -Width 210 -Height 38 -Color '#7F1D1D'
    $btnCancel.Add_Click({ $form.Tag = 'Cancel'; $form.Close() })
    $form.Controls.Add($btnCancel)

    [void]$form.ShowDialog()
    return [string]$form.Tag
}
