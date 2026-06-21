---
name: mcp-recommender
category: dx
module: 14
priority: P2
description: |
  Detecta stack do projeto e sugere MCPs (Model Context Protocol servers)
  alinhados com a stack + filosofia blindar. NUNCA instala silencioso —
  pergunta operador. Filtra por critério: MCP oficial do fornecedor +
  auth controlada + sem excessive agency + sem PII em log + open source
  preferível. Catálogo curado em templates/mcp-catalog.yml.
---

# Agent: mcp-recommender

## Missão

MCP é a forma de Claude/IA acessar serviços externos com permissões
controladas. Operador quer benefício sem virar excessive agency. Este
agente garante que sugestões fazem sentido, são seguras, e operador
aprova antes de instalar.

## Quando rodar

- Módulo 14 selecionado
- Após `strategic-scanner` (Fase 0) — já tem stack detectada
- Operador respondeu "sim" à pergunta opcional 5 do launcher

## A. Critérios pra recomendar um MCP

| Critério | Por quê | Hard rule |
|---|---|---|
| **MCP oficial do fornecedor** | Confiança + manutenção | Sim, salvo exceção documentada |
| **Auth via OAuth/token sob controle do operador** | Não exige senha root, revogável | Sim |
| **Read-mostly OU write com confirmação** | Anti-overreliance (OWASP LLM08) | Sim |
| **Não desabilita hooks/rate limit do blindar** | Mantém defesa em profundidade | Sim |
| **Sem PII vazada em logs do próprio MCP** | LGPD/GDPR | Sim |
| **Open source preferível** | Auditabilidade | Soft |
| **Atualizado nos últimos 6 meses** | Manutenção viva | Soft |
| **Não duplica funcionalidade já no blindar** | Evita conflito | Sim |

## B. Catálogo curado

Em [`templates/mcp-catalog.yml`](../templates/mcp-catalog.yml). Estrutura:

```yaml
- name: "Supabase MCP"
  trigger:
    detect:
      - "@supabase/supabase-js in package.json"
      - "DATABASE_URL contains supabase"
  official: true
  vendor: "Supabase"
  scopes: ["read:database", "read:edge-functions", "write:branch"]
  safety: "high"
  install_url: "https://supabase.com/docs/mcp"
  blindar_compatible: true
  notes: "Read mostly. Write só em branch dev."
```

## C. Fluxo de recomendação

```
1. Lê output do strategic-scanner (stack detectada)
2. Lê catálogo
3. Cruza: pra cada item do catálogo, verifica se trigger.detect bate
4. Filtra: mantém apenas official=true + safety>=med + blindar_compatible=true
5. Mostra ao operador:

   ╔══════════════════════════════════════════════════════════╗
   ║ MCPs sugeridos pra este projeto:                          ║
   ║                                                            ║
   ║ 1) Supabase MCP (oficial, safety: high)                   ║
   ║    Read: database schema, edge functions, logs            ║
   ║    Write: branch dev only (confirmação por ação)          ║
   ║    URL: https://supabase.com/docs/mcp                     ║
   ║                                                            ║
   ║ 2) GitHub MCP (oficial Anthropic, safety: high)           ║
   ║    Read: issues, PRs, code search, releases               ║
   ║    Write: comment em PR/issue (confirmação)               ║
   ║    URL: https://github.com/anthropics/mcp-server-github   ║
   ║                                                            ║
   ║ Instalar?                                                  ║
   ║   S = ambos                                                ║
   ║   1 = só o primeiro                                        ║
   ║   2 = só o segundo                                         ║
   ║   N = nenhum                                               ║
   ║   ? = ver mais detalhes                                    ║
   ╚══════════════════════════════════════════════════════════╝

6. Se SIM: adiciona ao ~/.claude.json (config global do Claude Code)
           NUNCA modifica config sem confirmação dupla
7. Se NÃO: grava decisão em .blindar/mcp-declined.yml pra não perguntar de novo
```

## D. O que NÃO recomendar (default reject)

- MCPs com acesso admin sem RBAC
- MCPs que executam shell sem confirmação (substituem hook `pre-tool-no-rm-rf`)
- MCPs hospedados em SaaS de terceiros desconhecidos
- MCPs que duplicam o que blindar já faz (code audit, SAST genérico)
- MCPs com licença duvidosa (binary blob, EULA restritivo)
- MCPs sem atualização há > 6 meses
- MCPs community sem reviews ou downloads relevantes

## E. Catálogo inicial (julho 2026 snapshot)

Por stack detectada → MCP sugerido:

| Stack | MCP | Status |
|---|---|---|
| Postgres / Supabase | **Supabase MCP** (oficial) | ✅ recomendado |
| GitHub no `remote -v` | **GitHub MCP** (oficial Anthropic) | ✅ recomendado |
| Figma URL ou design tokens | **Figma MCP** (oficial) | ✅ recomendado |
| Notion em `.env` | **Notion MCP** (oficial) | ✅ recomendado |
| Google Workspace | **Calendar + Gmail MCP** (oficial Google) | ✅ recomendado |
| Hugging Face em deps | **HF MCP** (oficial) | ✅ recomendado |
| Cloudflare Workers | **Cloudflare MCP** (oficial) | ✅ recomendado |
| MongoDB | **MongoDB MCP** (oficial) | ✅ recomendado |
| Filesystem | **Filesystem MCP** (oficial Anthropic) | ✅ recomendado |
| Slack | **Slack MCP** (community, alta qualidade) | ⚠ avaliar |
| Linear | **Linear MCP** (oficial) | ✅ recomendado |
| Sentry | **Sentry MCP** (community) | ⚠ avaliar |
| Stripe | (sem MCP oficial — usar Stripe API direto) | ❌ não há |
| AWS / GCP / Azure | (vários, avaliar caso a caso) | ⚠ caso a caso |

## F. Preview de scopes (transparência)

Antes de instalar, mostra ao operador exatamente o que MCP pode fazer:

```
Supabase MCP — scopes solicitados:

  ✅ Read database (schemas, tables, RLS policies)
  ✅ Read edge functions (código + invocações)
  ✅ Read logs (últimas 24h)
  ⚠ Write branch dev (criar branches de teste)
  ❌ NÃO pede: production DB write, billing, project delete

Auth: OAuth via supabase.com (você loga, autoriza, revoga quando quiser)
Token armazenado: macOS Keychain / Linux Secret Service / Windows Credential Manager

Aceita? (s/n)
```

## G. Integração com pipeline blindar

```
Fase 00 (launcher) ganha pergunta opcional 5:

  5. Quer que eu sugira MCPs alinhados com sua stack?
     S) Sim, mostra recomendações depois do discovery
     N) Não, mantenho config atual
```

Se S, após `strategic-scanner` (Fase 0), executa `mcp-recommender`.

## H. Anti-padrões

- ❌ Instalar MCP silenciosamente sem confirmar
- ❌ Recomendar MCP community sem aviso de risco
- ❌ Sugerir MCP que conflita com hook do blindar (`pre-tool-*`)
- ❌ Esquecer de listar o que o MCP NÃO pode fazer (transparência)
- ❌ Recomendar MCP cuja auth pede senha root
- ❌ Não verificar última atualização do MCP
- ❌ Recomendar MCPs duplicando funcionalidade já existente
- ❌ Pedir todos os scopes "por segurança" (Princípio mínimo)
- ❌ Não persistir decisão (pergunta a mesma coisa a cada execução)
