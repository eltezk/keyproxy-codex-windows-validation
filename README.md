# KeyProxy Hub + Codex CLI — pacote para o site

Este repositório é privado e gera uma entrega pronta. O proprietário precisa apenas:

> **Baixar o artifact → subir quatro arquivos → colar o HTML no portal.**

## COMECE AQUI

### 1. Baixe a entrega aprovada

1. Abra **Actions** neste repositório.
2. Entre na execução verde mais recente de **Release gate** na `main`.
3. Baixe o artifact **BAIXE-E-PUBLIQUE-NO-SITE**.
4. Extraia o arquivo.

Estrutura:

```text
LEIA-ME-PRIMEIRO.txt
UPLOAD-NO-SITE/
├── install.sh
├── install.sh.sha256
├── install.ps1
└── install.ps1.sha256
COPIAR-E-COLAR-NO-SITE.html
COPIAR-E-COLAR-NO-SITE.md
```

### 2. Suba os quatro arquivos

Envie todo o conteúdo de `UPLOAD-NO-SITE/`, sem editar, para:

```text
https://keyproxyhub.store/downloads/codex/
```

As URLs públicas finais serão:

```text
https://keyproxyhub.store/downloads/codex/install.sh
https://keyproxyhub.store/downloads/codex/install.sh.sha256
https://keyproxyhub.store/downloads/codex/install.ps1
https://keyproxyhub.store/downloads/codex/install.ps1.sha256
```

### 3. Cole a página dos clientes

- Portal com HTML: copie todo o conteúdo de `COPIAR-E-COLAR-NO-SITE.html`.
- Portal com Markdown: copie `COPIAR-E-COLAR-NO-SITE.md`.

Não é necessário editar URLs nem comandos.

### 4. Pacote unificado para operação técnica

A mesma execução do **Release gate** também publica o artifact privado `KEYPROXY-HUB-SETUP`. Ele contém menu único para Claude Code e Codex CLI em macOS/Linux e Windows, validação de checksums, status sanitizado, reversão confirmada somente do Claude e orientação manual segura para backups do Codex.

Esse artifact não substitui os quatro arquivos públicos de instalação Codex. Extraia-o e consulte `keyproxy-hub-setup/README.md` antes de executar o menu.

## Como ficou para o cliente

### Instalação rápida — macOS/Linux

```bash
curl -fLO https://keyproxyhub.store/downloads/codex/install.sh && bash install.sh
```

### Instalação rápida — Windows

```powershell
Invoke-WebRequest https://keyproxyhub.store/downloads/codex/install.ps1 -OutFile install.ps1; powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Esses comandos são curtos, mas não usam `curl | sh` nem `irm | iex`: o arquivo é salvo antes de ser executado. O portal oferece links para visualizar o script e o SHA-256, além de uma seção avançada com verificação completa.

No Windows, `ExecutionPolicy Bypass` vale somente para o processo que executa o instalador. Ele não muda permanentemente a política do computador.

## Por que isso transmite mais confiança

O trecho pronto para o portal mostra antes da execução:

- hospedagem HTTPS em `keyproxyhub.store`;
- o que o script faz e quais configurações altera;
- link para visualizar ou baixar cada script;
- link para o checksum SHA-256;
- verificação avançada opcional;
- aviso de que a API key não aparece na tela;
- backup e rollback da configuração local.

Não diga que o script é digitalmente assinado. O release atual é validado por SHA-256 e pelos runners do GitHub Actions, mas não possui certificado Authenticode de organização.

Para reduzir avisos do Windows/SmartScreen de forma adicional no futuro, será necessário adquirir um certificado de assinatura de código para a organização, assinar o `.ps1` e verificar a assinatura no release gate. Uma assinatura self-signed não deve ser apresentada aos clientes como prova de confiança.

## O que os instaladores fazem

1. verificam `codex --version`;
2. instalam ou reparam o Codex CLI pelo instalador oficial quando necessário;
3. solicitam a API key sem exibi-la;
4. configuram somente o modelo `gpt-5.6-sol`, a API e o MCP KeyProxy;
5. preservam preferências compatíveis e criam backup;
6. validam provider, modelo, MCP e conexão;
7. removem o OAuth oficial somente após uma conexão bem-sucedida (se o teste de API for ignorado, preservam o login);
8. fazem rollback se a validação local falhar.

Em VPS Linux por SSH, use um usuário normal (sem `sudo`), Bash ou Zsh e conectividade HTTPS/DNS para `chatgpt.com`, `releases.openai.com` e `api.keyproxyhub.store`. O instalador Bash exige `curl` quando precisar instalar ou reparar o Codex, para validar o destino final do download oficial. Para automação controlada, use `--api-key-stdin` e forneça a chave por canal protegido; nunca a passe como argumento nem use um comando que a deixe gravada no histórico do shell.

Compatibilidade:

- macOS com Bash ou Zsh;
- Linux com Bash;
- Windows PowerShell 5.1;
- PowerShell 7 no Windows;
- Windows 11 recomendado;
- Windows 10 build 17763+ em best effort;
- WSL usa o procedimento Linux.

## NÃO FAÇA ISSO

1. Não torne este repositório público para distribuir os scripts.
2. Não coloque API key, PAT GitHub ou credenciais do servidor no frontend.
3. Não edite os quatro arquivos depois de gerar a entrega; isso invalida o SHA-256.
4. Não publique self-tests, workflows, `.env`, logs, `scripts/` ou `.git`.
5. Não troque os comandos por `curl URL | sh`, `wget URL | sh` ou `irm URL | iex`.
6. Não afirme que existe assinatura digital enquanto não houver certificado e verificação Authenticode.

## Gerar a entrega localmente

Em macOS ou Linux:

```bash
bash scripts/build-public-bundle.sh
```

Saída:

```text
dist/keyproxy-codex-site/
dist/keyproxy-codex-site.zip
```

O builder copia os instaladores internos como `install.sh` e `install.ps1`, gera checksums com os nomes públicos e bloqueia arquivos internos, placeholders, links privados, pipes inseguros e alegações falsas de assinatura.

## Atualizar no futuro

1. Altere o instalador ou conteúdo do site em uma branch.
2. Se alterar um instalador interno, regenere seu checksum do repositório.
3. Revise o diff e integre na `main`.
4. Aguarde o **Release gate** verde em Ubuntu, Windows PowerShell 5.1 e PowerShell 7.
5. Baixe o novo artifact **BAIXE-E-PUBLIQUE-NO-SITE**.
6. Substitua os quatro arquivos públicos juntos.
7. Abra as quatro URLs em janela anônima.
8. Teste o fluxo curto em uma máquina descartável.

Checksums internos do repositório:

```bash
shasum -a 256 keyproxy-codex-install.sh > keyproxy-codex-install.sh.sha256
shasum -a 256 keyproxy-codex-install-windows.ps1 > keyproxy-codex-install-windows.ps1.sha256
bash scripts/build-public-bundle.sh
```

O `.ps1` interno permanece UTF-8 sem BOM e CRLF. Qualquer mudança de bytes exige novo checksum e gate Windows.

## Rollback

Guarde o artifact anterior aprovado. Se uma atualização apresentar problema:

1. restaure os quatro arquivos públicos do artifact anterior;
2. invalide o cache de `/downloads/codex/`, se houver CDN;
3. baixe novamente pelas URLs públicas;
4. verifique os hashes;
5. corrija em uma nova versão.

## Configuração do servidor/CDN

Recomendação:

```text
Content-Type: text/plain; charset=utf-8
X-Content-Type-Options: nosniff
Cache-Control: public, max-age=300, must-revalidate
```

Se `Content-Disposition` for usado, prefira `inline` para permitir que o cliente visualize o código no navegador; o comando continuará baixando normalmente. O CDN não pode minificar, converter encoding ou alterar finais de linha.

Links `raw.githubusercontent.com` do repositório privado não funcionam para clientes. Os quatro arquivos precisam ser servidos pelo domínio KeyProxy. Tokens GitHub ficam apenas no backend/CI.

## Release gate

`.github/workflows/release-gate.yml` valida:

- sintaxe e self-test no Ubuntu 24.04;
- Windows PowerShell 5.1 e `Get-FileHash`;
- PowerShell 7 em Windows nativo;
- entrega com exatamente quatro nomes públicos;
- checksums públicos;
- HTML e Markdown;
- domínio oficial, links de inspeção e seção avançada;
- ausência de placeholders, links privados e pipes inseguros.

A conta atual não oferece branch protection para repositório privado. Revisão do diff e gate verde são controles obrigatórios.

## Checklist do proprietário

- [ ] Baixei o artifact verde mais recente da `main`.
- [ ] Subi `install.sh`, `install.sh.sha256`, `install.ps1` e `install.ps1.sha256`.
- [ ] As quatro URLs funcionam sem login.
- [ ] Colei o HTML ou Markdown pronto.
- [ ] Os links “Ver script” e “Ver SHA-256” funcionam.
- [ ] Não publiquei credenciais nem aleguei assinatura digital inexistente.
- [ ] Testei o comando curto em ambiente descartável.
- [ ] Guardei o artifact anterior para rollback.
