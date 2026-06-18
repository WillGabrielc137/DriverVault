function Initialize-DriverVaultWinForms {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
}

function Get-ThemeColor {
    param(
        [string]$Hex
    )

    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

function New-DarkButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height = 34,
        [string]$Color = '#374151'
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.BackColor = Get-ThemeColor $Color
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderColor = Get-ThemeColor '#4B5563'
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)
    return $button
}

function New-DarkLabel {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height = 22
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.ForeColor = Get-ThemeColor '#E5E7EB'
    return $label
}

function New-DarkTextBox {
    param(
        [int]$X,
        [int]$Y,
        [int]$Width,
        [string]$Text = ''
    )

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point($X, $Y)
    $textBox.Size = New-Object System.Drawing.Size($Width, 24)
    $textBox.Text = $Text
    $textBox.BackColor = Get-ThemeColor '#1F2937'
    $textBox.ForeColor = Get-ThemeColor '#F9FAFB'
    $textBox.BorderStyle = 'FixedSingle'
    return $textBox
}
