function ConvertTo-OpenXmlText {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    $text = $text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ' '
    return [System.Security.SecurityElement]::Escape($text)
}

function New-DocxParagraphXml {
    param(
        [string]$Text,
        [string]$Style = 'Normal'
    )

    $styleXml = ''
    if ($Style -and $Style -ne 'Normal') {
        $styleXml = '<w:pPr><w:pStyle w:val="' + (ConvertTo-OpenXmlText $Style) + '"/></w:pPr>'
    }
    return '<w:p>' + $styleXml + '<w:r><w:t xml:space="preserve">' + (ConvertTo-OpenXmlText $Text) + '</w:t></w:r></w:p>'
}

function New-DocxTableXml {
    param(
        [string[]]$Headers,
        [object[]]$Rows
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('<w:tbl>')
    [void]$builder.Append('<w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="9CA3AF"/><w:left w:val="single" w:sz="4" w:space="0" w:color="9CA3AF"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="9CA3AF"/><w:right w:val="single" w:sz="4" w:space="0" w:color="9CA3AF"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="9CA3AF"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="9CA3AF"/></w:tblBorders></w:tblPr>')
    [void]$builder.Append('<w:tr>')
    foreach ($header in $Headers) {
        [void]$builder.Append('<w:tc><w:tcPr><w:shd w:fill="E5E7EB"/></w:tcPr><w:p><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">')
        [void]$builder.Append((ConvertTo-OpenXmlText $header))
        [void]$builder.Append('</w:t></w:r></w:p></w:tc>')
    }
    [void]$builder.Append('</w:tr>')

    if (@($Rows).Count -eq 0) {
        [void]$builder.Append('<w:tr><w:tc><w:tcPr><w:gridSpan w:val="' + $Headers.Count + '"/></w:tcPr><w:p><w:r><w:t>Nenhum registro.</w:t></w:r></w:p></w:tc></w:tr>')
    }
    else {
        foreach ($row in $Rows) {
            [void]$builder.Append('<w:tr>')
            foreach ($header in $Headers) {
                $value = ''
                if ($row -is [hashtable] -and $row.ContainsKey($header)) {
                    $value = $row[$header]
                }
                elseif ($row.PSObject.Properties[$header]) {
                    $value = $row.PSObject.Properties[$header].Value
                }
                [void]$builder.Append('<w:tc><w:p><w:r><w:t xml:space="preserve">')
                [void]$builder.Append((ConvertTo-OpenXmlText $value))
                [void]$builder.Append('</w:t></w:r></w:p></w:tc>')
            }
            [void]$builder.Append('</w:tr>')
        }
    }

    [void]$builder.Append('</w:tbl>')
    return $builder.ToString()
}

function Get-UniqueReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $folder = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    for ($i = 2; $i -lt 1000; $i++) {
        $candidate = Join-Path $folder ("{0}_{1}{2}" -f $base, $i, $ext)
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return (Join-Path $folder ("{0}_{1}{2}" -f $base, (Get-Date -Format 'HHmmssfff'), $ext))
}

function Initialize-DriverReportFolder {
    $state = Get-DriverVaultState
    if (-not (Test-Path -LiteralPath $state.ReportRoot -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $state.ReportRoot | Out-Null
    }
    return (Resolve-Path -LiteralPath $state.ReportRoot).Path
}

function New-DriverReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,
        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    $reportRoot = Initialize-DriverReportFolder
    $server = ConvertTo-SafeFileName -Name (Get-DriverVaultServerName)
    $safeAction = ConvertTo-SafeFileName -Name $Action
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    return Get-UniqueReportPath -Path (Join-Path $reportRoot ("Relatorio_{0}_{1}_{2}.{3}" -f $safeAction, $server, $stamp, $Extension.TrimStart('.')))
}

function ConvertTo-MarkdownCell {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }
    return ([string]$Value -replace '\|', '/' -replace '\r?\n', ' ').Trim()
}

function New-MarkdownTable {
    param(
        [string[]]$Headers,
        [object[]]$Rows
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('| ' + (($Headers | ForEach-Object { ConvertTo-MarkdownCell $_ }) -join ' | ') + ' |')
    $lines.Add('| ' + (($Headers | ForEach-Object { '---' }) -join ' | ') + ' |')

    if (@($Rows).Count -eq 0) {
        $emptyValues = @('Nenhum registro.')
        for ($i = 1; $i -lt $Headers.Count; $i++) {
            $emptyValues += ''
        }
        $lines.Add('| ' + ($emptyValues -join ' | ') + ' |')
    } else {
        foreach ($row in @($Rows)) {
            $values = foreach ($header in $Headers) {
                if ($row -is [hashtable] -and $row.ContainsKey($header)) {
                    ConvertTo-MarkdownCell $row[$header]
                } elseif ($row.PSObject.Properties[$header]) {
                    ConvertTo-MarkdownCell $row.PSObject.Properties[$header].Value
                } else {
                    ''
                }
            }
            $lines.Add('| ' + ($values -join ' | ') + ' |')
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function New-DriverVaultDocxReport {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Drivers,
        [object[]]$Duplicados,
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [string]$ReportPath = ''
    )

    $state = Get-DriverVaultState
    $server = Get-DriverVaultServerName
    $reportPath = if ([string]::IsNullOrWhiteSpace($ReportPath)) { New-DriverReportPath -Action 'Backup' -Extension 'docx' } else { $ReportPath }

    $copiedDrivers = @($Drivers | Where-Object { $_.Status -eq 'Copiado' -or $_.Status -eq 'Parcial' })
    $warnings = @($Drivers | Where-Object { $_.Avisos -or $_.Erros })

    $summaryRows = @(
        [pscustomobject]@{ Campo = 'Nome do servidor'; Valor = $server },
        [pscustomobject]@{ Campo = 'Data/hora da geracao'; Valor = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') },
        [pscustomobject]@{ Campo = 'Usuario'; Valor = ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) },
        [pscustomobject]@{ Campo = 'Acao executada'; Valor = 'Backup' },
        [pscustomobject]@{ Campo = 'Nome da pasta de backup'; Valor = (Split-Path -Leaf $BackupPath) },
        [pscustomobject]@{ Campo = 'Quantidade de drivers encontrados'; Valor = @($Drivers).Count },
        [pscustomobject]@{ Campo = 'Quantidade de drivers copiados'; Valor = $copiedDrivers.Count },
        [pscustomobject]@{ Campo = 'Quantidade de possiveis duplicados'; Valor = @($Duplicados).Count },
        [pscustomobject]@{ Campo = 'Caminho final do backup'; Valor = $BackupPath },
        [pscustomobject]@{ Campo = 'Manifesto'; Valor = (Join-Path $BackupPath 'drivers-manifest.json') },
        [pscustomobject]@{ Campo = 'Log tecnico'; Valor = $state.CurrentLogFile }
    )

    $driverRows = @($Drivers | ForEach-Object {
            [pscustomobject]@{
                Driver      = $_.Driver
                Fabricante  = $_.Fabricante
                Versao      = $_.Versao
                Arquitetura = $_.Arquitetura
                Status      = $_.Status
                Arquivos    = $_.ArquivosCopiados
                INF         = $_.PrimaryInfPath
                Catalogo    = $_.CatalogPath
                Assinatura  = $_.CatalogSignatureStatus
                Backup      = $_.CaminhoBackup
            }
        })

    $duplicateRows = @($Duplicados | ForEach-Object {
            [pscustomobject]@{
                Referencia       = $_.DriverReferencia
                VersaoReferencia = $_.VersaoReferencia
                NovoDriver       = $_.NovoDriver
                NovaVersao       = $_.NovaVersao
                Similaridade     = $_.Similaridade
                Motivo           = $_.Motivo
            }
        })

    $errorRows = @($warnings | ForEach-Object {
            [pscustomobject]@{
                Driver = $_.Driver
                Avisos = $_.Avisos
                Erros  = $_.Erros
            }
        })

    $body = New-Object System.Text.StringBuilder
    [void]$body.Append((New-DocxParagraphXml -Text 'Relatorio final de backup de drivers de impressora' -Style 'Title'))
    [void]$body.Append((New-DocxParagraphXml -Text 'Resumo' -Style 'Heading1'))
    [void]$body.Append((New-DocxTableXml -Headers @('Campo', 'Valor') -Rows $summaryRows))
    [void]$body.Append((New-DocxParagraphXml -Text 'Drivers copiados' -Style 'Heading1'))
    [void]$body.Append((New-DocxTableXml -Headers @('Driver', 'Fabricante', 'Versao', 'Arquitetura', 'Status', 'Arquivos', 'INF', 'Catalogo', 'Assinatura', 'Backup') -Rows $driverRows))
    [void]$body.Append((New-DocxParagraphXml -Text 'Drivers duplicados ou suspeitos' -Style 'Heading1'))
    [void]$body.Append((New-DocxTableXml -Headers @('Referencia', 'VersaoReferencia', 'NovoDriver', 'NovaVersao', 'Similaridade', 'Motivo') -Rows $duplicateRows))
    [void]$body.Append((New-DocxParagraphXml -Text 'Erros encontrados' -Style 'Heading1'))
    [void]$body.Append((New-DocxTableXml -Headers @('Driver', 'Avisos', 'Erros') -Rows $errorRows))

    $documentXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:w10="urn:schemas-microsoft-com:office:word" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup" xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk" xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" mc:Ignorable="w14 wp14">
  <w:body>
    $($body.ToString())
    <w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>
  </w:body>
</w:document>
"@

    $stylesXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:rFonts w:ascii="Segoe UI" w:hAnsi="Segoe UI"/><w:sz w:val="20"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="36"/><w:color w:val="111827"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="360" w:after="120"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="1F2937"/></w:rPr></w:style>
  <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:color="9CA3AF"/><w:left w:val="single" w:sz="4" w:color="9CA3AF"/><w:bottom w:val="single" w:sz="4" w:color="9CA3AF"/><w:right w:val="single" w:sz="4" w:color="9CA3AF"/><w:insideH w:val="single" w:sz="4" w:color="9CA3AF"/><w:insideV w:val="single" w:sz="4" w:color="9CA3AF"/></w:tblBorders></w:tblPr></w:style>
</w:styles>
"@

    $contentTypesXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>
"@

    $rootRelsXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"@

    $documentRelsXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"@

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('DriverVaultDocx_' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot '_rels') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'word\_rels') | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot '[Content_Types].xml') -Value $contentTypesXml -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $tempRoot '_rels\.rels') -Value $rootRelsXml -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $tempRoot 'word\document.xml') -Value $documentXml -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $tempRoot 'word\styles.xml') -Value $stylesXml -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $tempRoot 'word\_rels\document.xml.rels') -Value $documentRelsXml -Encoding UTF8

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempRoot, $reportPath)
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    $state.LastReportPath = $reportPath
    Write-DriverVaultLog ("Relatorio DOCX gerado: {0}" -f $reportPath)
    return $reportPath
}

function New-DriverVaultMarkdownReport {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Drivers,
        [object[]]$Duplicados,
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [string]$DocxError = '',
        [string]$DocxPathAttempted = ''
    )

    $state = Get-DriverVaultState
    $reportPath = New-DriverReportPath -Action 'Backup' -Extension 'md'
    $manifestPath = Join-Path $BackupPath 'drivers-manifest.json'
    $copiedDrivers = @($Drivers | Where-Object { $_.Status -eq 'Copiado' -or $_.Status -eq 'Parcial' })
    $ignoredDrivers = @($Drivers | Where-Object { $_.Status -like 'Ignorado*' })
    $errorDrivers = @($Drivers | Where-Object { $_.Erros -or $_.Avisos -or $_.Status -like '*incompleto*' -or $_.Status -like '*Erro*' })

    $summaryRows = @(
        [pscustomobject]@{ Campo = 'Data/hora da geracao'; Valor = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') },
        [pscustomobject]@{ Campo = 'Servidor'; Valor = Get-DriverVaultServerName },
        [pscustomobject]@{ Campo = 'Usuario'; Valor = ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) },
        [pscustomobject]@{ Campo = 'Acao'; Valor = 'Backup' },
        [pscustomobject]@{ Campo = 'Backup'; Valor = $BackupPath },
        [pscustomobject]@{ Campo = 'Manifesto'; Valor = $manifestPath },
        [pscustomobject]@{ Campo = 'Drivers encontrados'; Valor = @($Drivers).Count },
        [pscustomobject]@{ Campo = 'Drivers salvos'; Valor = $copiedDrivers.Count },
        [pscustomobject]@{ Campo = 'Drivers ignorados'; Valor = $ignoredDrivers.Count },
        [pscustomobject]@{ Campo = 'Duplicidades'; Valor = @($Duplicados).Count },
        [pscustomobject]@{ Campo = 'Log'; Valor = $state.CurrentLogFile }
    )

    $driverRows = @($Drivers | ForEach-Object {
        [pscustomobject]@{
            Driver = $_.Driver
            Fabricante = $_.Fabricante
            Versao = $_.Versao
            Arquitetura = $_.Arquitetura
            Status = $_.Status
            INF = $_.PrimaryInfPath
            Catalogo = $_.CatalogPath
            Assinatura = $_.CatalogSignatureStatus
            Certificado = $_.CatalogSignerThumbprint
            Erros = $_.Erros
            Avisos = $_.Avisos
        }
    })

    $duplicateRows = @($Duplicados | ForEach-Object {
        [pscustomobject]@{
            Referencia = $_.DriverReferencia
            VersaoReferencia = $_.VersaoReferencia
            NovoDriver = $_.NovoDriver
            NovaVersao = $_.NovaVersao
            Motivo = $_.Motivo
        }
    })

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Relatorio de Backup de Drivers')
    $lines.Add('')
    if ($DocxError) {
        $lines.Add('> O DOCX nao foi gerado. Este arquivo Markdown foi criado como fallback.')
        if ($DocxPathAttempted) {
            $lines.Add("> Caminho DOCX tentado: $DocxPathAttempted")
        }
        $lines.Add("> Erro: $DocxError")
        $lines.Add('')
    }
    $lines.Add('## Resumo')
    $lines.Add((New-MarkdownTable -Headers @('Campo', 'Valor') -Rows $summaryRows))
    $lines.Add('')
    $lines.Add('## Drivers Envolvidos')
    $lines.Add((New-MarkdownTable -Headers @('Driver', 'Fabricante', 'Versao', 'Arquitetura', 'Status', 'INF', 'Catalogo', 'Assinatura', 'Certificado', 'Erros', 'Avisos') -Rows $driverRows))
    $lines.Add('')
    $lines.Add('## Duplicidades')
    $lines.Add((New-MarkdownTable -Headers @('Referencia', 'VersaoReferencia', 'NovoDriver', 'NovaVersao', 'Motivo') -Rows $duplicateRows))
    $lines.Add('')
    $lines.Add('## Observacoes')
    $lines.Add('- O backup deve conter o pacote completo do DriverStore.')
    $lines.Add('- Arquivos INF descrevem o pacote do driver.')
    $lines.Add('- Arquivos CAT guardam o catalogo de assinatura exigido pelo Windows.')
    $lines.Add('- Drivers com CAT ausente nao devem ser restaurados em servidores reais.')

    Set-Content -LiteralPath $reportPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
    $state.LastReportPath = $reportPath
    Write-DriverVaultLog ("Relatorio Markdown gerado: {0}" -f $reportPath)
    return $reportPath
}

function New-DriverVaultReport {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Drivers,
        [object[]]$Duplicados,
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    $attemptedPath = ''
    try {
        $attemptedPath = New-DriverReportPath -Action 'Backup' -Extension 'docx'
        return New-DriverVaultDocxReport -Drivers $Drivers -Duplicados $Duplicados -BackupPath $BackupPath -ReportPath $attemptedPath
    } catch {
        $message = "Falha ao gerar relatorio DOCX. Caminho tentado: $attemptedPath. Erro: $($_.Exception.Message)"
        Write-DriverVaultLog $message 'ERROR'
        return New-DriverVaultMarkdownReport -Drivers $Drivers -Duplicados $Duplicados -BackupPath $BackupPath -DocxError $_.Exception.Message -DocxPathAttempted $attemptedPath
    }
}

function New-DriverRestoreReport {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Drivers,
        [string]$BackupPath = '',
        [string]$Action = 'Restauracao'
    )

    $state = Get-DriverVaultState
    $reportPath = New-DriverReportPath -Action $Action -Extension 'md'
    $selected = @($Drivers | Where-Object { $_.Selected })
    $installed = @($Drivers | Where-Object { $_.Status -eq 'Instalado' })
    $ignored = @($Drivers | Where-Object { $_.Status -like 'Ignorado*' })
    $failed = @($Drivers | Where-Object { $_.Erros -or $_.Status -like '*Falha*' -or $_.Status -like '*incompleto*' })

    $summaryRows = @(
        [pscustomobject]@{ Campo = 'Data/hora da geracao'; Valor = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') },
        [pscustomobject]@{ Campo = 'Servidor'; Valor = Get-DriverVaultServerName },
        [pscustomobject]@{ Campo = 'Usuario'; Valor = ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) },
        [pscustomobject]@{ Campo = 'Acao'; Valor = $Action },
        [pscustomobject]@{ Campo = 'Backup usado'; Valor = $BackupPath },
        [pscustomobject]@{ Campo = 'Drivers disponiveis'; Valor = @($Drivers).Count },
        [pscustomobject]@{ Campo = 'Drivers selecionados'; Valor = $selected.Count },
        [pscustomobject]@{ Campo = 'Drivers instalados'; Valor = $installed.Count },
        [pscustomobject]@{ Campo = 'Drivers ignorados'; Valor = $ignored.Count },
        [pscustomobject]@{ Campo = 'Drivers com erro'; Valor = $failed.Count },
        [pscustomobject]@{ Campo = 'Log'; Valor = $state.CurrentLogFile }
    )

    $driverRows = @($Drivers | ForEach-Object {
        [pscustomobject]@{
            Driver = $_.Driver
            Fabricante = $_.Fabricante
            Versao = $_.Versao
            Selecionado = $_.Selected
            Status = $_.Status
            INF = $_.InfPath
            Catalogo = $_.CatalogPath
            Assinatura = $_.CatalogSignatureStatus
            Certificado = $_.CatalogSignerThumbprint
            Erros = $_.Erros
            Avisos = $_.Avisos
        }
    })

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Relatorio de Restauracao de Drivers')
    $lines.Add('')
    $lines.Add('## Resumo')
    $lines.Add((New-MarkdownTable -Headers @('Campo', 'Valor') -Rows $summaryRows))
    $lines.Add('')
    $lines.Add('## Drivers')
    $lines.Add((New-MarkdownTable -Headers @('Driver', 'Fabricante', 'Versao', 'Selecionado', 'Status', 'INF', 'Catalogo', 'Assinatura', 'Certificado', 'Erros', 'Avisos') -Rows $driverRows))
    $lines.Add('')
    $lines.Add('## Observacoes')
    $lines.Add('- A restauracao usa pnputil com caminho completo do INF.')
    $lines.Add('- A instalacao real exige administrador.')
    $lines.Add('- A importacao de certificado so deve ocorrer com confirmacao explicita do usuario.')

    Set-Content -LiteralPath $reportPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
    $state.LastReportPath = $reportPath
    Write-DriverVaultLog ("Relatorio Markdown de restauracao gerado: {0}" -f $reportPath)
    return $reportPath
}
