function New-DuplicateDriver {
    param(
        [object]$Referencia,
        [object]$Novo,
        [double]$Similaridade,
        [string]$Motivo
    )

    [pscustomobject]@{
        DriverReferencia      = $Referencia.Driver
        VersaoReferencia      = $Referencia.Versao
        FabricanteReferencia  = $Referencia.Fabricante
        ArquiteturaReferencia = $Referencia.Arquitetura
        OrigemReferencia      = ConvertTo-SafeText -Value $Referencia.CaminhoBackup -Default (ConvertTo-SafeText -Value $Referencia.OrigemManifesto -Default $Referencia.Origem)
        NovoDriver            = $Novo.Driver
        NovaVersao            = $Novo.Versao
        FabricanteNovo        = $Novo.Fabricante
        ArquiteturaNovo       = $Novo.Arquitetura
        OrigemNovo            = ConvertTo-SafeText -Value $Novo.CaminhoBackup -Default (ConvertTo-SafeText -Value $Novo.OrigemManifesto -Default $Novo.Origem)
        Similaridade          = ('{0:P0}' -f $Similaridade)
        Motivo                = $Motivo
    }
}
