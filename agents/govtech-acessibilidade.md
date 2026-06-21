---
name: govtech-acessibilidade
category: vertical
module: 10
priority: P1
description: |
  Govtech BR: eMAG (Modelo de Acessibilidade em Governo Eletrônico),
  ePING (interoperabilidade), gov.br SSO (login único cidadão), LAI
  (Lei 12.527/2011 — acesso à informação), transparência ativa,
  VLibras, formatos abertos. Diferente de WCAG genérico — este é o
  perfil BR de gov, com gates específicos pra órgãos públicos federais,
  estaduais e municipais. Falha aqui = TCU/CGU notification + ação MP.
---

# Agent: govtech-acessibilidade

## Missão

Sistemas públicos brasileiros (federal/estadual/municipal) e empresas
contratadas pelo gov BR. eMAG é o padrão oficial (Portaria SLTI MP
03/2007, atualizada). ePING define interoperabilidade. gov.br SSO é o
identity provider único do cidadão. LAI obriga transparência ativa.

Sem isso: TCU pode determinar refazimento; CGU pode aplicar sanção;
Ministério Público pode mover ação civil pública por exclusão digital.

WCAG cobre o universal. Este agente cobre **o específico BR**.

## Quando rodar

- Módulo 10 selecionado
- Projeto declara natureza pública (`gov.br` no domínio, contrato com
  órgão público, licitação)
- Detecção via grep: `gov.br`, `vlibras`, `lai`, `acessibilidade`,
  `emag`, `transparencia`
- Pula silencioso se zero indício de gov

## A. eMAG — visão geral

Modelo de Acessibilidade em Governo Eletrônico, versão 3.1. Estrutura
em 6 seções, 45 recomendações. Núcleo prático:

### Marcação (1.x)
- 1.1 Respeitar padrões web (HTML válido W3C)
- 1.3 **Atalhos de teclado**: Alt+1 conteúdo, Alt+2 menu, Alt+3 busca, Alt+4 rodapé
- 1.5 **Mapa do site** acessível em todas as páginas (link no rodapé)
- 1.9 Não abrir nova janela sem aviso
- 1.10 **Botão "Acessibilidade"** visível no header (link pra página)

### Comportamento (2.x)
- 2.1 **Indicação visual de foco** (`:focus` com outline ≥ 2px contraste 3:1)
- 2.2 Não usar elementos que piscam (epilepsy)
- 2.3 Tempo suficiente pra leitura/interação (configurável)

### Conteúdo/informação (3.x)
- 3.1 Identificar `lang="pt-br"` em `<html>`
- 3.5 Hierarquia de cabeçalhos (`h1` → `h2` → `h3` sem pular)
- 3.6 Listas reais (`<ul>`, `<ol>`, `<dl>`)

### Apresentação/design (4.x)
- 4.1 Não usar tabela pra layout
- 4.4 **Versão alto contraste** (toggle no botão Acessibilidade)
- 4.5 Tamanho de fonte ajustável (botões A-, A, A+)

### Multimídia (5.x)
- 5.1 Legendas em vídeo
- 5.2 Audiodescrição em vídeo
- 5.5 Documento em formato aberto (`.odt`, `.html`) além de `.pdf`
- 5.6 PDF acessível (texto selecionável, tags, ordem de leitura) — não imagem digitalizada

### Formulário (6.x)
- 6.1 `<label>` associado a input
- 6.2 Agrupar campos relacionados com `<fieldset>`
- 6.5 Mensagem de erro descritiva + posicionada próxima ao campo

## B. ePING — interoperabilidade

Padrões de Interoperabilidade de Governo Eletrônico. Pontos práticos:

- **APIs**: REST + JSON (XML legado aceito)
- **Autenticação**: OAuth 2.0 + OIDC com gov.br
- **Datas**: ISO 8601 com timezone `-03:00`
- **CEP/CPF/CNPJ**: validação obrigatória + máscara
- **Catalogação**: dados publicados em [dados.gov.br](https://dados.gov.br)

## C. gov.br SSO

Identity provider único do cidadão (RFB + ITI). Níveis:

- **Bronze**: auto-cadastro
- **Prata**: validação bancária OU biometria facial
- **Ouro**: ICP-Brasil ou validação presencial

Sistemas públicos DEVEM aceitar login gov.br. Implementação:

```ts
// .well-known/openid-configuration:
// https://sso.staging.acesso.gov.br/.well-known/openid-configuration
// (prod) https://sso.acesso.gov.br/.well-known/openid-configuration

const issuer = 'https://sso.acesso.gov.br';
const scopes = ['openid', 'profile', 'email', 'govbr_confiabilidades'];
```

Login próprio pode coexistir, mas gov.br é OBRIGATÓRIO como opção.

## D. LAI — Lei 12.527/2011

Transparência ativa obriga publicação proativa SEM solicitação:

- `/transparencia` — receitas, despesas, contratos, licitações
- `/dados-abertos` — datasets em formato aberto (CSV, JSON, XML)
- Estrutura organizacional
- Servidores + remunerações
- Convênios e parcerias

Transparência passiva: e-SIC integrado (Sistema Eletrônico do SIC) ou
formulário próprio.

Atualização mínima: dados orçamentários em tempo real (até D+1).

## E. VLibras

Tradutor automático português → Libras, mantido pelo MCom. Embed:

```html
<div vw class="enabled">
  <div vw-access-button class="active"></div>
  <div vw-plugin-wrapper>
    <div class="vw-plugin-top-wrapper"></div>
  </div>
</div>
<script src="https://vlibras.gov.br/app/vlibras-plugin.js"></script>
<script>new window.VLibras.Widget('https://vlibras.gov.br/app');</script>
```

Recomendado (não obrigatório legal) em todo portal gov. CGU considera
boa prática.

## F. CSP compatível com leitor de tela

Algumas extensões de leitor (NVDA, Jaws via plugin) injetam scripts.
CSP MUITO restritiva quebra. Permitir:

```
script-src 'self' https://vlibras.gov.br https://www.gov.br;
connect-src 'self' https://sso.acesso.gov.br;
frame-src 'self' https://vlibras.gov.br;
```

## G. Documentos públicos — formato

- Texto: HTML preferido > ODT > DOCX > PDF acessível
- PDF: NUNCA digitalização-imagem; sempre com tags + texto selecionável
- Planilha: CSV > ODS > XLSX
- Apresentação: ODP > PPTX

Validar PDF com **PAC 2024** (PDF Accessibility Checker) ou
`pdfix-validator`.

## H. Greps

```bash
# Login gov.br ausente em sistema público
rg -n "(login|signin|auth)" --type ts --type tsx -A 5 \
  | rg -v "(gov\\.br|govbr|acesso\\.gov)"

# Botão acessibilidade
rg -n "(acessibilidade|accessibility)" --type tsx --type html

# Atalhos teclado eMAG
rg -n "accesskey=" --type tsx --type html
rg -n "(Alt\\+1|alt\\+1|accessKey)" --type ts --type tsx

# lang pt-br
rg -n "<html" --type tsx --type html | rg -v 'lang="pt-br"'

# VLibras
rg -n "vlibras" --type tsx --type html --type js

# /transparencia + /dados-abertos
rg -n "(transparencia|dados-abertos)" --type tsx --type ts

# PDF imagem (suspeito)
find . -name "*.pdf" -not -path "*/node_modules/*" 2>/dev/null | head -20
```

## I. Output em sec.html

```
┌─ Govtech & Acessibilidade BR (Módulo 10) ────────────────┐
│ Login gov.br SSO                  : ✅ OIDC nível Prata  │
│ Botão Acessibilidade (eMAG 1.10)  : ✅ no header         │
│ Atalhos Alt+1/2/3 (eMAG 1.3)      : ✅                   │
│ Indicação visual de foco (2.1)    : ✅ outline 3:1       │
│ Versão alto contraste (4.4)       : ✅ toggle            │
│ Mapa do site (eMAG 1.5)           : ✅ rodapé            │
│ lang="pt-br" em <html>            : ✅                   │
│ Documentos públicos acessíveis    : ✅ HTML + PDF tagged │
│ /transparencia + /dados-abertos   : ✅ LAI               │
│ VLibras embed                     : ✅                   │
│ CSP permite VLibras + gov.br      : ✅                   │
│ ePING (REST+JSON, OIDC, ISO 8601) : ✅                   │
│ Status                            : ✅ GOVTECH-READY    │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Sistema público SEM opção login gov.br (CRIT — diretriz federal)
- ❌ Sem botão "Acessibilidade" visível (HIGH — eMAG 1.10)
- ❌ Sem atalhos Alt+1/2/3/4 (HIGH — eMAG 1.3)
- ❌ `:focus { outline: none }` sem substituto (CRIT — eMAG 2.1)
- ❌ Sem versão alto contraste (HIGH — eMAG 4.4)
- ❌ `<html>` sem `lang="pt-br"` (HIGH)
- ❌ PDF público em imagem digitalizada não-OCR (HIGH — exclusão digital)
- ❌ Órgão público sem `/transparencia` ou `/dados-abertos` (MED — LAI)
- ❌ CSP restritiva demais — bloqueia VLibras/leitor (MED)
- ❌ Datas sem timezone `-03:00` (ePING)
- ❌ Login próprio bonito + gov.br escondido em link minúsculo
- ❌ Vídeo institucional sem legenda + audiodescrição
- ❌ Form com erro inline sem `aria-describedby`
- ❌ Tabela usada pra layout
