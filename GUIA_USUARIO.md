# Guia do Usuário — DriverVault

Este guia é destinado a equipes de suporte e administradores que precisam fazer backup ou restaurar drivers de impressora em máquinas e servidores Windows.

## 1. Abrir o DriverVault

Na raiz do projeto, execute:

```text
Executar_DriverVault.cmd
```

Também é possível abrir diretamente:

```text
App\Start-DriverVault.vbs
```

Execução manual:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\App\DriverVault.ps1
```

## 2. Executar como administrador

Para restaurar drivers, importar certificados ou realizar operações protegidas, execute o DriverVault como administrador.

Clique com o botão direito no launcher ou abra um PowerShell elevado antes de executar o comando manual.

## 3. Listar e selecionar drivers para backup

1. Abra a aba `Fazer backup dos drivers`.
2. Clique em `Listar drivers`.
3. Aguarde o inventário.
4. Marque apenas os drivers que devem ser copiados.
5. Confira a quantidade selecionada antes de continuar.

Drivers não selecionados não são enviados para exportação ou cópia detalhada.

## 4. Criar o backup

1. Clique em `Selecionar pasta`.
2. Escolha a pasta principal onde o backup será salvo.
3. Informe um nome para a subpasta do backup.
4. Clique em `Iniciar backup`.

Exemplo de nome:

```text
Backup_SRV01_2026-06
```

Se o nome ficar vazio, o DriverVault cria um nome baseado no servidor e na data/hora. Se a pasta já existir, a aplicação pergunta se deve usá-la, escolher outro nome ou cancelar.

## 5. Conteúdo do backup

Por padrão, backups locais ficam em:

```text
Backups\
```

Um backup pode conter:

- pacotes de drivers;
- arquivos INF e CAT;
- DLLs e arquivos auxiliares;
- subpastas de idioma;
- certificados exportados;
- `drivers-manifest.json`;
- metadados de validação.

Ao transferir um backup para outro servidor, copie a pasta inteira. Copiar somente o INF normalmente não é suficiente.

## 6. Localizar drivers para restauração

1. Abra o DriverVault como administrador no servidor de destino.
2. Abra a aba `Instalar/restaurar drivers`.
3. Selecione a pasta do backup.
4. Clique em `Localizar drivers`.
5. Aguarde a listagem leve.

O DriverVault lê primeiro o manifesto. Quando ele não existe, a aplicação procura arquivos INF de forma limitada e cancelável.

Essa listagem não instala nada e não executa validações profundas.

## 7. Selecionar e instalar

1. Use o filtro para localizar os drivers desejados.
2. Marque somente os itens que devem ser processados.
3. Confira `Drivers encontrados`, `Drivers selecionados` e `Exibindo`.
4. Clique em `Instalar selecionados`.

Somente os drivers selecionados seguem para:

- validação do INF e do CAT;
- conferência dos arquivos do pacote;
- verificação de assinatura e certificado;
- análise de possíveis duplicidades;
- execução do `pnputil`.

## 8. Driver já instalado

Quando um driver correspondente já existe, o DriverVault mostra informações do item do backup e do item instalado.

Opções:

- `Substituir`: tenta remover, atualizar ou substituir o driver existente.
- `Ignorar / manter existente`: mantém o driver atual e não instala o item do backup.
- `Cancelar`: interrompe o processo.

Em produção, use `Substituir` somente com janela de manutenção e plano de reversão.

## 9. INF ausente

Se o INF não for encontrado:

1. confirme que a pasta correta foi selecionada;
2. verifique se a pasta completa do backup foi copiada;
3. refaça o backup na máquina de origem se o pacote estiver incompleto.

## 10. CAT, assinatura e certificado

O CAT é o catálogo usado pelo Windows para validar a integridade e a assinatura do pacote.

Se o CAT estiver ausente, o pacote é considerado incompleto. Se o certificado não for confiável, o DriverVault solicita uma decisão antes de importá-lo em `Cert:\LocalMachine\TrustedPublisher`.

Antes de autorizar:

1. confirme a procedência do driver;
2. confira emissor e thumbprint;
3. valide a autorização conforme a política da empresa;
4. cancele em caso de dúvida.

O DriverVault não importa certificados silenciosamente.

## 11. Gerar relatório

Na aba correspondente ao processo executado, clique em `Gerar relatorio`.

Os relatórios são criados somente quando solicitados e ficam em:

```text
Relatorios\
```

O formato preferencial é DOCX. Se a geração falhar, a aplicação cria um arquivo Markdown.

## 12. Consultar e apagar logs

Os logs técnicos ficam em:

```text
Logs\
```

Use `Apagar logs` para remover os arquivos gerenciados nessa pasta. A ação exige confirmação e não pode ser desfeita pela aplicação.

## 13. Apagar relatórios

Use `Apagar relatorios` para limpar os arquivos gerenciados em `Relatorios`.

Essa ação também exige confirmação.

## 14. Criar atalho

Execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\App\CriarAtalhoDriverVault.ps1
```

O atalho padrão é criado como `DriverVault.lnk` na área de trabalho.

## 15. Cuidados antes de usar em produção

- Teste o fluxo em homologação.
- Preserve uma cópia do backup original.
- Confira se o pacote contém INF, CAT e arquivos auxiliares.
- Verifique a assinatura e a origem do certificado.
- Marque somente os drivers necessários.
- Evite substituir drivers durante o horário de uso.
- Gere um relatório após operações importantes.
