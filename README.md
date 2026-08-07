# KeyProxy Hub — instaladores do Codex CLI

Repositório **privado** de origem dos instaladores KeyProxy Hub para Codex CLI em macOS, Linux e Windows. Este documento é o manual operacional do proprietário do KeyProxy: validação, publicação no site/CDN, conteúdo para o portal de clientes, atualização e rollback.

> **Nunca torne este repositório público apenas para distribuir os scripts.** O portal deve servir uma cópia controlada dos quatro artefatos públicos. Links `raw.githubusercontent.com` de um repositório privado exigem autenticação e não funcionam para clientes anônimos.

## 1. O que o instalador configura

Os dois instaladores verificam primeiro se o Codex CLI oficial está instalado e funcional. Quando ausente — ou quando `codex --version` falha — baixam o instalador oficial para um arquivo temporário, validam sua sintaxe, executam-no sem pipe direto e validam novamente o Codex. Somente depois solicitam a chave do cliente e configuram:

- modelo exclusivo: `gpt-5.6-sol`;
- provider: `keyproxy`;
- Responses API: `https://api.keyproxyhub.store/v1`;
- MCP HTTP: `https://api.keyproxyhub.store/mcp`;
- autenticação da API e do MCP pela variável `KEYPROXY_API_KEY`;
- `requires_openai_auth = false`;
- apps oficiais desativados;
- remoção do login OAuth oficial com `codex logout`.

A API key **não está no repositório**, não é gravada no `config.toml` e não pode ser adicionada ao site, README, workflow, release ou checksum.

## 2. Arquivos e limites de publicação

### Arquivos que o site pode expor publicamente

| Plataforma | Instalador | Checksum |
|---|---|---|
| macOS e Linux | `keyproxy-codex-install.sh` | `keyproxy-codex-install.sh.sha256` |
| Windows nativo | `keyproxy-codex-install-windows.ps1` | `keyproxy-codex-install-windows.ps1.sha256` |

### Arquivos que permanecem privados

- `keyproxy-codex-unix-selftest.sh`;
- `keyproxy-codex-windows-native-selftest.ps1`;
- `.github/workflows/`;
- `scripts/build-public-bundle.sh`;
- este manual e o histórico Git.

O comando abaixo monta `dist/public/` contendo somente os quatro arquivos públicos e verifica os dois hashes:

```bash
bash scripts/build-public-bundle.sh
```

Não publique a raiz do repositório nem use `rsync --delete` contra uma origem não revisada. Publique apenas o conteúdo de `dist/public/`.

## 3. Arquitetura recomendada

```text
GitHub privado
   │
   │ checkout autenticado no backend/CI
   ▼
release gate + dist/public/
   │
   │ upload autenticado pelo backend/CI
   ▼
storage privado de origem ── CDN/site público
                              │
                              ▼
                         novos clientes
```

Regras obrigatórias:

1. O token GitHub fica somente em secrets do CI ou no backend do KeyProxy.
2. Nunca inclua PAT, token GitHub ou credencial de storage no JavaScript entregue ao navegador.
3. O frontend aponta apenas para URLs HTTPS públicas do domínio KeyProxy.
4. O backend/CI copia bytes revisados; ele não executa os instaladores.
5. O CDN deve servir os scripts como download, sem transformá-los, minificá-los ou normalizar finais de linha.
6. Os checksums devem ser publicados ao lado dos bytes exatos que representam.
7. Mantenha pelo menos a versão anterior para rollback.

### URLs públicas recomendadas

URLs estáveis, usadas no portal:

```text
https://keyproxyhub.store/downloads/codex/keyproxy-codex-install.sh
https://keyproxyhub.store/downloads/codex/keyproxy-codex-install.sh.sha256
https://keyproxyhub.store/downloads/codex/keyproxy-codex-install-windows.ps1
https://keyproxyhub.store/downloads/codex/keyproxy-codex-install-windows.ps1.sha256
```

URLs imutáveis, usadas para auditoria e rollback:

```text
https://keyproxyhub.store/downloads/codex/releases/VERSAO/keyproxy-codex-install.sh
https://keyproxyhub.store/downloads/codex/releases/VERSAO/keyproxy-codex-install.sh.sha256
https://keyproxyhub.store/downloads/codex/releases/VERSAO/keyproxy-codex-install-windows.ps1
https://keyproxyhub.store/downloads/codex/releases/VERSAO/keyproxy-codex-install-windows.ps1.sha256
```

Use uma versão explícita, por exemplo `2026.08.07.1`. Faça primeiro o upload para a URL imutável; após validar o download público, promova os mesmos bytes para as URLs estáveis.

### Headers recomendados

```text
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="NOME-DO-ARQUIVO"
X-Content-Type-Options: nosniff
Cache-Control (versionado): public, max-age=31536000, immutable
Cache-Control (estável): public, max-age=300, must-revalidate
```

Se o site usar CSP, storage em outro hostname ou CORS, libere apenas o domínio de downloads necessário. O download via navegação não exige credenciais do GitHub.

## 4. Preparação única do repositório privado

O repositório deve continuar com visibilidade `PRIVATE`. Dê acesso de escrita apenas a mantenedores autorizados e ative 2FA nas contas.

Cadastre no CI somente os secrets necessários ao storage/CDN, por exemplo:

```text
KEYPROXY_DOWNLOADS_ENDPOINT
KEYPROXY_DOWNLOADS_BUCKET
KEYPROXY_DOWNLOADS_ACCESS_KEY_ID
KEYPROXY_DOWNLOADS_SECRET_ACCESS_KEY
KEYPROXY_CDN_DISTRIBUTION_ID       # se houver invalidação
```

Os nomes são exemplos; adapte ao provedor. Use credenciais com permissão limitada ao prefixo `downloads/codex/`, sem acesso administrativo global.

O GitHub já fornece `GITHUB_TOKEN` ao workflow. Para checkout do próprio repositório não é necessário criar PAT. Se um pipeline externo consumir este repositório, prefira GitHub App com acesso somente a este repositório; use fine-grained PAT apenas quando GitHub App não for possível.

> A conta atual não oferece branch protection para repositório privado. Enquanto isso, trate o release gate verde e a revisão manual do diff como controles obrigatórios. Caso o plano do GitHub seja atualizado, exija o workflow **Release gate** antes de atualizar `main`.

## 5. Gate antes de cada publicação

O workflow `.github/workflows/release-gate.yml` valida em runners reais:

- Ubuntu 24.04: sintaxe Bash, SHA-256, bootstrap isolado e bundle público;
- Windows PowerShell 5.1: self-test nativo e `Get-FileHash`;
- PowerShell 7 no Windows: self-test nativo.

Os self-tests usam Codex e chave fictícios. Não alteram o Codex real de um cliente e não contêm uma API key de produção.

### Processo obrigatório

1. Atualize os scripts em uma branch.
2. Revise o diff e procure segredos.
3. Regenere o checksum de todo instalador alterado.
4. Execute testes locais disponíveis.
5. Envie a branch e revise antes de integrar a `main`.
6. Execute o workflow **Release gate** na `main`.
7. Só publique se todos os jobs estiverem verdes.
8. Baixe o artifact `keyproxy-codex-public-bundle` do workflow ou gere o bundle a partir do mesmo commit.
9. Registre o commit e a versão no controle interno de release.

Checksums locais:

```bash
shasum -a 256 keyproxy-codex-install.sh > keyproxy-codex-install.sh.sha256
shasum -a 256 keyproxy-codex-install-windows.ps1 > keyproxy-codex-install-windows.ps1.sha256
bash scripts/build-public-bundle.sh
```

O instalador Windows deve permanecer UTF-8 sem BOM e CRLF. Não salve o `.ps1` com uma ferramenta que altere silenciosamente esses bytes sem regenerar seu checksum e repetir o gate Windows.

## 6. Publicação manual segura

Este exemplo é propositalmente independente de fornecedor. Primeiro gere o bundle:

```bash
VERSION="2026.08.07.1"
bash scripts/build-public-bundle.sh
find dist/public -maxdepth 1 -type f -print
```

Depois envie **somente** os quatro arquivos de `dist/public/` para:

```text
downloads/codex/releases/$VERSION/
```

Use a CLI autenticada do storage no computador do mantenedor ou no CI. Exemplos de operações conceituais:

```text
UPLOAD dist/public/* -> downloads/codex/releases/$VERSION/
DOWNLOAD downloads/codex/releases/$VERSION/* -> diretório temporário
COMPARE hashes locais e baixados
COPY os mesmos objetos -> downloads/codex/
INVALIDATE apenas /downloads/codex/*, se necessário
```

Não copie um comando genérico de upload para produção sem ajustar ao storage real, permissões, cache e domínio. Nunca passe credenciais na linha de comando se elas puderem aparecer no histórico; use o secret store do CI ou o mecanismo nativo de autenticação do provedor.

## 7. Modelo de deploy automatizado

O job de deploy deve depender do sucesso do gate e usar um environment protegido, por exemplo `keyproxy-downloads-production`. Estrutura recomendada:

```yaml
name: Publish installers

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Versão imutável, por exemplo 2026.08.07.1'
        required: true

permissions:
  contents: read

jobs:
  validate:
    # Reutilize os mesmos comandos do release-gate.yml ou transforme-o
    # futuramente em workflow_call.
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v5
      - run: bash scripts/build-public-bundle.sh dist/public
      - uses: actions/upload-artifact@v4
        with:
          name: public-bundle
          path: dist/public/

  publish:
    needs: validate
    runs-on: ubuntu-24.04
    environment: keyproxy-downloads-production
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: public-bundle
          path: dist/public
      - name: Upload versioned objects
        run: ./COMANDO-DO-STORAGE dist/public "downloads/codex/releases/${{ inputs.version }}/"
      - name: Download and verify versioned objects
        run: ./COMANDO-DE-VERIFICACAO "${{ inputs.version }}"
      - name: Promote exact bytes to stable URLs
        run: ./COMANDO-DE-PROMOCAO "${{ inputs.version }}" "downloads/codex/"
```

Esse trecho é um **molde**, não um workflow funcional até que os três comandos sejam implementados para o storage do KeyProxy. Não adicione uma etapa que busque os arquivos diretamente de `raw.githubusercontent.com` no navegador do cliente.

## 8. Verificação obrigatória após o deploy

Baixe novamente os quatro arquivos a partir do domínio público; não valide apenas os arquivos locais.

### macOS ou Linux

```bash
set -Eeuo pipefail
URL_BASE="https://keyproxyhub.store/downloads/codex"
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT

curl -fL "$URL_BASE/keyproxy-codex-install.sh" \
  -o "$VERIFY_DIR/keyproxy-codex-install.sh"
curl -fL "$URL_BASE/keyproxy-codex-install.sh.sha256" \
  -o "$VERIFY_DIR/keyproxy-codex-install.sh.sha256"
curl -fL "$URL_BASE/keyproxy-codex-install-windows.ps1" \
  -o "$VERIFY_DIR/keyproxy-codex-install-windows.ps1"
curl -fL "$URL_BASE/keyproxy-codex-install-windows.ps1.sha256" \
  -o "$VERIFY_DIR/keyproxy-codex-install-windows.ps1.sha256"

(
  cd "$VERIFY_DIR"
  shasum -a 256 -c keyproxy-codex-install.sh.sha256
  EXPECTED="$(awk 'NR == 1 { print tolower($1) }' keyproxy-codex-install-windows.ps1.sha256)"
  ACTUAL="$(shasum -a 256 keyproxy-codex-install-windows.ps1 | awk '{ print tolower($1) }')"
  test "$ACTUAL" = "$EXPECTED"
)
```

### Windows

```powershell
$Base = 'https://keyproxyhub.store/downloads/codex'
$Dir = Join-Path $env:TEMP ("keyproxy-verify-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Dir | Out-Null
try {
    $Script = Join-Path $Dir 'keyproxy-codex-install-windows.ps1'
    $Checksum = "$Script.sha256"
    Invoke-WebRequest -Uri "$Base/keyproxy-codex-install-windows.ps1" -OutFile $Script
    Invoke-WebRequest -Uri "$Base/keyproxy-codex-install-windows.ps1.sha256" -OutFile $Checksum
    $Expected = (Get-Content $Checksum -Raw).Split()[0].ToLowerInvariant()
    $Actual = (Get-FileHash $Script -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected) { throw "SHA-256 divergente: $Actual" }
    [scriptblock]::Create((Get-Content $Script -Raw)) | Out-Null
    Write-Host "Deploy Windows confirmado: $Actual"
} finally {
    Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
}
```

Além do hash:

- confirme HTTP `200` e HTTPS válido;
- confirme que a resposta não é uma página HTML de login/erro;
- confirme `Content-Disposition` e `X-Content-Type-Options`;
- confirme que URL versionada e estável possuem o mesmo SHA-256;
- faça um smoke test em ambiente descartável, sem usar uma chave real nos logs;
- verifique que nenhuma URL do portal aponta para o GitHub privado.

## 9. Conteúdo pronto para a página de novos clientes

A seção abaixo pode ser copiada para o portal público.

---

### Configurar Codex CLI com KeyProxy Hub

O instalador verifica se o Codex CLI está funcional. Se necessário, instala ou repara o Codex usando o instalador oficial; depois solicita sua API key sem exibi-la e configura o modelo `gpt-5.6-sol`, a API e o MCP do KeyProxy.

#### macOS ou Linux

Abra o Terminal e execute:

```bash
mkdir -p "$HOME/Downloads/keyproxy-codex" && cd "$HOME/Downloads/keyproxy-codex"
URL_BASE="https://keyproxyhub.store/downloads/codex"
curl -fL "$URL_BASE/keyproxy-codex-install.sh" -o keyproxy-codex-install.sh
curl -fL "$URL_BASE/keyproxy-codex-install.sh.sha256" -o keyproxy-codex-install.sh.sha256
shasum -a 256 -c keyproxy-codex-install.sh.sha256 2>/dev/null || sha256sum -c keyproxy-codex-install.sh.sha256
chmod 700 keyproxy-codex-install.sh
./keyproxy-codex-install.sh
```

Quando solicitado, cole sua API key KeyProxy e pressione Enter. A chave não aparece na tela. Não execute com `sudo` ou como `root`.

#### Windows nativo

Abra o **Windows PowerShell** ou **PowerShell 7** como usuário normal — não use “Executar como administrador” — e execute:

```powershell
$Dir = Join-Path $HOME 'Downloads\keyproxy-codex'
New-Item -ItemType Directory -Path $Dir -Force | Out-Null
Set-Location $Dir
$Base = 'https://keyproxyhub.store/downloads/codex'
Invoke-WebRequest -Uri "$Base/keyproxy-codex-install-windows.ps1" -OutFile '.\keyproxy-codex-install-windows.ps1'
Invoke-WebRequest -Uri "$Base/keyproxy-codex-install-windows.ps1.sha256" -OutFile '.\keyproxy-codex-install-windows.ps1.sha256'
$Expected = (Get-Content '.\keyproxy-codex-install-windows.ps1.sha256' -Raw).Split()[0].ToLowerInvariant()
$Actual = (Get-FileHash '.\keyproxy-codex-install-windows.ps1' -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw "SHA-256 divergente. Esperado: $Expected; obtido: $Actual" }
Write-Host "SHA-256 confirmado: $Actual"
```

No Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\keyproxy-codex-install-windows.ps1'
```

No PowerShell 7:

```powershell
pwsh.exe -NoProfile -File '.\keyproxy-codex-install-windows.ps1'
```

Quando solicitado, cole sua API key KeyProxy e pressione Enter. Abra um novo terminal após a instalação. Windows 11 é recomendado; Windows 10 build 17763+ possui suporte best effort.

**WSL:** dentro do WSL, use o procedimento macOS/Linux. Não execute o instalador PowerShell nativo de dentro da distribuição Linux.

#### Segurança

- Baixe o script e o checksum antes de executar.
- Interrompa se a verificação SHA-256 falhar.
- Nunca use `curl URL | sh`, `wget URL | sh` ou `irm URL | iex`.
- Nunca informe sua API key a terceiros ou em tickets públicos.
- Para rotacionar a chave, execute novamente o mesmo instalador.

---

## 10. Release, promoção e rollback

### Lançar uma nova versão

1. Crie uma versão imutável.
2. Registre o commit exato da `main`.
3. Confirme o **Release gate** verde nesse commit.
4. Gere ou baixe o bundle público desse mesmo commit.
5. Faça upload para `releases/VERSAO/`.
6. Baixe de volta e compare hashes.
7. Promova os mesmos objetos para as URLs estáveis.
8. Invalide somente o cache estável, se necessário.
9. Repita a verificação pública.
10. Atualize o registro interno com versão, commit, hashes, responsável e data.

### Rollback

1. Não edite um release imutável já publicado.
2. Escolha a última versão conhecida como válida.
3. Copie seus quatro objetos versionados para as URLs estáveis.
4. Invalide o cache estável.
5. Baixe novamente e confirme os hashes.
6. Registre o incidente e o rollback.
7. Corrija em uma nova versão; nunca sobrescreva silenciosamente a versão defeituosa.

### Checklist de aprovação

- [ ] Repositório continua privado.
- [ ] Diff revisado por mantenedor autorizado.
- [ ] Nenhuma API key, PAT ou secret aparece nos arquivos ou logs.
- [ ] Checksums foram regenerados depois da última alteração de bytes.
- [ ] Release gate verde em Ubuntu, Windows PowerShell 5.1 e PowerShell 7.
- [ ] Bundle contém exatamente quatro arquivos públicos.
- [ ] Upload versionado concluído.
- [ ] Download versionado validado por SHA-256.
- [ ] URLs estáveis promovidas a partir dos mesmos bytes.
- [ ] Download estável validado por SHA-256.
- [ ] Portal não contém links do GitHub privado.
- [ ] Versão anterior permanece disponível para rollback.

## 11. Compatibilidade e evidência atual

Cobertura automatizada do repositório:

- macOS: Bash e Zsh, por self-test isolado executado no gate de desenvolvimento;
- Linux: Ubuntu 24.04 Bash;
- Windows: Windows PowerShell 5.1 e PowerShell 7 em runner Windows nativo;
- Windows 11 x64 recomendado;
- Windows 10 build 17763+ em best effort;
- ARM64 e x64 dependem do suporte do instalador oficial do Codex.

Os workflows comprovam sintaxe, merge, bootstrap ausente/inválido, idempotência, rollback e checksums com dependências fictícias. Uma execução real autenticada depende da disponibilidade da API, MCP, chave, cota e rede do ambiente e deve ser feita apenas de forma autorizada, sem registrar a chave.

## 12. Segurança operacional

- Nunca publique uma API key no repositório, no site ou em screenshots.
- Nunca use a chave de um cliente em CI.
- Rotacione imediatamente qualquer chave exposta.
- Não transforme a chave em parâmetro de linha de comando.
- Não sirva os arquivos por HTTP sem TLS.
- Não altere os scripts no CDN; toda mudança nasce em Git, passa pelo gate e recebe novo hash.
- Não publique self-tests, logs, `.env`, artifacts de diagnóstico ou o diretório `.git`.
- Não use lógica de encerramento de processos para instalar ou testar o Codex.
- Preserve o histórico de versões e os hashes para auditoria.
