# KeyProxy Hub + Codex CLI — pacote para o site

Este repositório privado gera um pacote pronto para o proprietário do KeyProxy publicar. O fluxo é simples:

> **Baixar um artifact → subir 4 arquivos → copiar um trecho no site.**

## COMECE AQUI

### 1. Baixe o pacote aprovado

1. Abra a aba **Actions** deste repositório.
2. Abra a execução verde mais recente do workflow **Release gate** na branch `main`.
3. Em **Artifacts**, baixe **BAIXE-E-PUBLIQUE-NO-SITE**.
4. Extraia o arquivo baixado.

A entrega terá esta estrutura:

```text
keyproxy-codex-site/
├── LEIA-ME-PRIMEIRO.txt
├── UPLOAD-NO-SITE/
│   ├── keyproxy-codex-install.sh
│   ├── keyproxy-codex-install.sh.sha256
│   ├── keyproxy-codex-install-windows.ps1
│   └── keyproxy-codex-install-windows.ps1.sha256
├── COPIAR-E-COLAR-NO-SITE.html
└── COPIAR-E-COLAR-NO-SITE.md
```

### 2. Suba os 4 arquivos

Envie **todo o conteúdo** de `UPLOAD-NO-SITE/`, sem editar ou renomear, para:

```text
https://keyproxyhub.store/downloads/codex/
```

Ao terminar, estas URLs precisam abrir ou baixar arquivos:

```text
https://keyproxyhub.store/downloads/codex/keyproxy-codex-install.sh
https://keyproxyhub.store/downloads/codex/keyproxy-codex-install.sh.sha256
https://keyproxyhub.store/downloads/codex/keyproxy-codex-install-windows.ps1
https://keyproxyhub.store/downloads/codex/keyproxy-codex-install-windows.ps1.sha256
```

### 3. Cole o guia no site

- Se o editor do portal aceita HTML, abra `COPIAR-E-COLAR-NO-SITE.html` e copie todo o conteúdo.
- Se o editor aceita Markdown, use `COPIAR-E-COLAR-NO-SITE.md`.

Os textos já possuem as URLs finais do KeyProxy. Não é necessário substituir domínio ou editar comandos.

### 4. Teste antes de liberar

1. Abra as quatro URLs acima em uma janela anônima.
2. Confirme que nenhuma URL pede login no GitHub.
3. Use uma máquina de teste e siga exatamente o guia do cliente.
4. Não coloque uma chave real em logs, screenshots ou tickets.

## O que o cliente precisa fazer

O cliente escolhe sua plataforma, copia **um único bloco**, cola no Terminal/PowerShell e informa a API key quando solicitado.

O instalador cuida automaticamente de:

1. localizar o Codex CLI;
2. verificar `codex --version`;
3. instalar ou reparar o Codex quando necessário;
4. solicitar a API key sem mostrá-la;
5. configurar exclusivamente `gpt-5.6-sol`, API e MCP KeyProxy;
6. remover o OAuth oficial anterior;
7. validar a configuração e testar a conexão.

Compatibilidade:

- macOS com Bash ou Zsh;
- Linux com Bash;
- Windows PowerShell 5.1;
- PowerShell 7 no Windows;
- Windows 11 recomendado;
- Windows 10 build 17763+ em best effort;
- no WSL, o cliente usa o procedimento Linux.

## NÃO FAÇA ISSO

1. **Não torne este repositório público.** Clientes recebem arquivos pelo domínio KeyProxy, não pelo GitHub privado.
2. **Não publique credenciais.** Nunca coloque API key, PAT GitHub ou senha do servidor nos scripts, no portal ou no frontend.
3. **Não edite os quatro arquivos depois de gerar o pacote.** Qualquer alteração invalida o SHA-256.
4. Não publique self-tests, `.github`, logs, `.env`, `scripts/` ou o histórico `.git`.
5. Não use comandos como `curl URL | sh`, `wget URL | sh` ou `irm URL | iex`.

## Se preferir gerar o pacote localmente

Em macOS ou Linux, dentro do repositório:

```bash
bash scripts/build-public-bundle.sh
```

A entrega será criada em:

```text
dist/keyproxy-codex-site/
dist/keyproxy-codex-site.zip
```

O builder:

- copia somente os quatro arquivos públicos;
- adiciona o guia curto e os trechos HTML/Markdown;
- confere os dois checksums;
- bloqueia self-tests, `.env`, logs e arquivos internos;
- bloqueia links privados, placeholders e execução insegura por pipe.

## Atualizar os instaladores no futuro

1. Altere o instalador necessário em uma branch.
2. Regenere seu checksum.
3. Envie a alteração e revise o diff.
4. Integre na `main`.
5. Aguarde o **Release gate** ficar verde em Linux, Windows PowerShell 5.1 e PowerShell 7.
6. Baixe o novo artifact **BAIXE-E-PUBLIQUE-NO-SITE**.
7. Substitua os quatro arquivos do site **juntos**.
8. Abra as quatro URLs e refaça o teste do cliente.

Checksums locais:

```bash
shasum -a 256 keyproxy-codex-install.sh > keyproxy-codex-install.sh.sha256
shasum -a 256 keyproxy-codex-install-windows.ps1 > keyproxy-codex-install-windows.ps1.sha256
bash scripts/build-public-bundle.sh
```

O `.ps1` precisa permanecer UTF-8 sem BOM e com CRLF. Se os bytes mudarem, regenere o checksum e execute novamente o gate Windows.

## Rollback rápido

Mantenha uma cópia do pacote anterior aprovado.

Se a nova publicação apresentar problema:

1. substitua os quatro arquivos públicos pelos quatro arquivos do pacote anterior;
2. limpe ou invalide o cache de `/downloads/codex/`, se houver CDN;
3. baixe novamente os arquivos pelas URLs públicas;
4. confirme os hashes;
5. corrija a falha em uma nova versão, sem editar silenciosamente o pacote antigo.

## Como o site deve servir os arquivos

Configuração recomendada:

```text
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="NOME-DO-ARQUIVO"
X-Content-Type-Options: nosniff
Cache-Control: public, max-age=300, must-revalidate
```

O CDN/storage não pode minificar, recomprimir, converter encoding ou alterar finais de linha dos scripts.

### GitHub privado

Links `raw.githubusercontent.com` de repositórios privados não funcionam para clientes anônimos. O GitHub permanece apenas como origem e validação. O site/CDN deve servir uma cópia dos arquivos.

- Tokens GitHub ficam somente no backend/CI.
- Nunca coloque PAT no JavaScript do portal.
- Para checkout deste próprio repositório nos Actions, use o `GITHUB_TOKEN` já fornecido pelo GitHub.
- Se um sistema externo precisar ler o repositório, prefira GitHub App com acesso somente a ele.

## Release gate

O arquivo `.github/workflows/release-gate.yml` executa:

- Ubuntu 24.04: sintaxe Bash, checksum, self-test isolado e geração da entrega;
- Windows PowerShell 5.1: self-test nativo e `Get-FileHash`;
- PowerShell 7 no Windows: self-test nativo;
- validações do HTML, Markdown, domínio, placeholders e conteúdo publicável.

Os self-tests usam Codex e chave fictícios. Não dependem da conta ou chave de um cliente.

A conta atual não oferece branch protection para repositório privado. Por isso, a revisão do diff e o **Release gate verde** são obrigatórios antes de publicar.

## Checklist final do proprietário

- [ ] Baixei o artifact verde mais recente da `main`.
- [ ] Subi exatamente os quatro arquivos de `UPLOAD-NO-SITE/`.
- [ ] As quatro URLs públicas funcionam sem login.
- [ ] Colei o HTML ou Markdown pronto no portal.
- [ ] Não adicionei nenhuma credencial ao site.
- [ ] Testei o fluxo macOS/Linux ou Windows em ambiente descartável.
- [ ] Mantive o pacote anterior para rollback.
