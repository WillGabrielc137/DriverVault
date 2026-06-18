# DriverVault

Aplicação Windows para inventariar, fazer backup, validar e restaurar drivers de impressora com controle explícito do usuário.

O DriverVault foi desenvolvido em PowerShell e WinForms para apoiar equipes de suporte e administração de servidores Windows. A aplicação tenta preservar o pacote completo de cada driver, gera um manifesto técnico e mantém validações de INF, catálogo e certificado restritas aos drivers selecionados.

## Funcionalidades principais

- Listagem de drivers de impressora instalados.
- Seleção individual dos drivers antes do backup.
- Exportação de pacotes pelo `pnputil` quando o pacote está disponível no DriverStore.
- Cópia complementar de INF, CAT, DLLs, arquivos de idioma e subpastas do pacote.
- Geração do manifesto técnico `drivers-manifest.json`.
- Listagem leve e cancelável de backups para restauração.
- Seleção individual dos drivers antes da validação e instalação.
- Validação de INF, CAT, arquivos auxiliares, assinatura e certificado.
- Detecção de possíveis duplicidades.
- Registro de logs técnicos.
- Geração de relatórios DOCX ou Markdown sob demanda.
- Limpeza controlada das pastas de logs e relatórios.

## Requisitos

- Windows com Windows PowerShell 5.1 ou versão compatível.
- WinForms disponível.
- `pnputil.exe`, incluído nas versões atuais do Windows.
- Serviço de impressão e recursos de gerenciamento de impressoras disponíveis para inventário completo.
- Permissão de administrador para restaurar drivers, importar certificados ou realizar operações protegidas.

Não há dependências externas para instalar e o Microsoft Word não é necessário. O relatório DOCX é montado diretamente no formato OpenXML/ZIP; se essa geração falhar, o DriverVault cria um relatório Markdown.

## Preparação do ambiente

1. Copie ou clone o projeto para uma pasta local.
2. Mantenha toda a estrutura interna do projeto.
3. Para restauração de drivers, abra o launcher ou o PowerShell como administrador.
4. Se a política de execução bloquear scripts, use um dos launchers fornecidos, que inicia o PowerShell com `ExecutionPolicy Bypass` apenas para o processo atual.

As pastas `Backups`, `Logs` e `Relatorios` são criadas automaticamente quando necessário.

## Como executar

### Launcher principal

Na raiz do projeto:

```text
Executar_DriverVault.cmd
```

Esse comando chama o launcher VBS e mantém a janela do PowerShell oculta.

### Launcher VBS

```powershell
wscript.exe .\App\Start-DriverVault.vbs
```

### Launcher BAT

```text
App\Start-DriverVault.bat
```

### Execução manual no PowerShell

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\App\DriverVault.ps1
```

### Criar um atalho na área de trabalho

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\App\CriarAtalhoDriverVault.ps1
```

Por padrão, o script cria `DriverVault.lnk` na área de trabalho. Um caminho diferente pode ser informado pelo parâmetro `-ShortcutPath`.

## Autotestes

O inicializador oferece verificações que não abrem a interface:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\App\DriverVault.ps1 -SelfTest -SelfTestMode Import -NoGuiError
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\App\DriverVault.ps1 -SelfTest -SelfTestMode Duplicate -NoGuiError
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\App\DriverVault.ps1 -SelfTest -SelfTestMode DocxMock -NoGuiError
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\App\DriverVault.ps1 -SelfTest -SelfTestMode All -NoGuiError
```

Modos disponíveis:

- `Import`: confirma o carregamento dos módulos e a inicialização do contexto.
- `Duplicate`: verifica a lógica básica de similaridade de nomes.
- `DocxMock`: gera um relatório DOCX temporário.
- `All`: executa todas as verificações.

## Fluxo de backup

1. Abra a aba de backup.
2. Liste os drivers instalados.
3. Marque somente os drivers desejados.
4. Escolha a pasta de destino e o nome do backup.
5. Inicie o backup.

Para cada item selecionado, o DriverVault tenta associar o driver ao pacote real do Windows e pode executar:

```powershell
pnputil /enum-drivers
pnputil /export-driver <PublishedName> <Destino>
```

Drivers não selecionados não seguem para exportação, cópia detalhada ou processamento do pacote.

## Fluxo de restauração

1. Abra a aba de restauração.
2. Selecione a pasta que contém o backup.
3. Clique em `Localizar drivers`.
4. Aguarde a listagem leve.
5. Use o filtro se houver muitos itens.
6. Marque somente os drivers desejados.
7. Clique em `Instalar selecionados`.

O DriverVault usa `drivers-manifest.json` como fonte principal do inventário. Se não houver manifesto, realiza uma varredura leve e limitada por arquivos INF.

Durante a listagem, a aplicação não faz validação profunda, não verifica duplicidade detalhada, não trata certificados e não chama o `pnputil`. Essas etapas ocorrem somente depois da seleção e apenas para os drivers selecionados.

Antes da instalação de cada item selecionado, são verificados:

- caminho e existência do INF;
- catálogo CAT referenciado;
- arquivos auxiliares do pacote;
- assinatura e certificado do catálogo;
- possível driver correspondente já instalado.

## Manifesto técnico

Cada backup registra, quando disponível:

- nome, versão, fabricante e arquitetura;
- `OriginalInfName` e `PublishedName`;
- caminhos relativos de INF e CAT;
- estado da assinatura;
- thumbprint do certificado;
- origem da exportação;
- resultado e mensagens de validação.

Os caminhos operacionais são preferencialmente relativos à pasta do backup para permitir a cópia do pacote para outro servidor.

## Relatórios

Os relatórios são gerados somente quando o usuário solicita pela interface, por meio do botão `Gerar relatorio`.

Destino:

```text
Relatorios\
```

O formato preferencial é DOCX. Quando a criação do DOCX falha, é produzido um arquivo Markdown como fallback. Os relatórios podem incluir servidor, usuário, ação executada, drivers processados, sucessos, falhas, manifesto e diagnósticos de INF, CAT e certificado.

## Logs

Os logs ficam em:

```text
Logs\
```

O botão `Apagar logs` remove os arquivos gerenciados dentro dessa pasta. Logs, relatórios e backups são dados locais de execução e estão excluídos do Git.

## Estrutura do projeto

```text
DriverVault/
|-- App/
|   |-- DriverVault.ps1
|   |-- Start-DriverVault.vbs
|   |-- Start-DriverVault.bat
|   |-- CriarAtalhoDriverVault.ps1
|   |-- Core/
|   |   |-- Backup/
|   |   |-- PnP/
|   |   |-- Restore/
|   |   |-- Utils/
|   |   `-- Validation/
|   |-- Models/
|   `-- UI/
|       `-- Panels/
|-- docs/
|   `-- GUIA_USUARIO.md
|-- Backups/        # gerada localmente e ignorada pelo Git
|-- Logs/           # gerada localmente e ignorada pelo Git
|-- Relatorios/     # gerada localmente e ignorada pelo Git
|-- Executar_DriverVault.cmd
|-- .editorconfig
|-- .gitattributes
|-- .gitignore
`-- README.md
```

## Organização interna

- `App/DriverVault.ps1`: ponto de entrada e carregamento dos módulos.
- `App/Core`: regras de negócio, serviços de backup, restauração, manifesto, assinatura, relatórios e manutenção.
- `App/Models`: objetos usados pelos fluxos de backup e restauração.
- `App/UI`: janelas, painéis, tema, diálogos e estado visual.
- `docs`: documentação complementar.
- `Backups`, `Logs` e `Relatorios`: dados operacionais locais, não versionados.

## Manutenção futura

- Preserve o carregamento centralizado em `App/DriverVault.ps1`.
- Ao criar um serviço, registre o arquivo na lista `$requiredScripts` ou em um agregador já carregado.
- Não processe drivers não selecionados. A seleção do usuário deve continuar sendo uma barreira antes de exportação, validação, certificado, duplicidade detalhada e instalação.
- Mantenha a listagem de restauração leve, incremental, limitada e cancelável.
- Prefira caminhos relativos dentro dos backups para manter a portabilidade entre máquinas.
- Não instale certificados silenciosamente.
- Não desative a validação de assinatura do Windows.
- Execute os autotestes após alterar nomes de funções, caminhos, módulos ou serviços.
- Atualize este README e o guia do usuário quando o comportamento operacional mudar.

## Preparação para GitHub

Os artefatos locais de execução já estão cobertos pelo `.gitignore`. Antes do primeiro envio:

```powershell
git status
git add .
git diff --cached --check
git commit -m "feat: prepare DriverVault project"
git remote add origin <URL_DO_REPOSITORIO>
git push -u origin main
```

Não adicione manualmente o conteúdo de `Backups`, `Logs` ou `Relatorios`. Revise também se algum backup contém drivers, certificados ou dados cuja distribuição não seja autorizada.

## Limitações e cuidados

- A exportação depende de o pacote estar publicado no DriverStore.
- Drivers antigos ou não assinados podem ser recusados por versões recentes do Windows.
- Alguns ambientes exigem privilégios administrativos até para completar o inventário.
- Teste restaurações primeiro em homologação.
- Confirme a procedência do driver e do certificado antes de importar ou instalar.
- Evite substituir drivers em produção sem janela de manutenção e plano de reversão.

Consulte também o [Guia do Usuário](docs/GUIA_USUARIO.md).
