---
name: mcp-security
category: core
module: 2
priority: P0
description: |
  Audita segurança dos MCPs JÁ CONECTADOS (diferente de mcp-recommender
  que SUGERE). Cobre capability bleed, prompt injection via tool output,
  escopo excessivo, MCPs sem update há >6m, MCPs community sem auth
  review, tokens em plain text no config. Lê ~/.claude.json ou config
  do Claude Desktop pra listar MCPs ativos e cruza com whitelist de
  safety em templates/mcp-catalog.yml.
---

# Agent: mcp-security

Auditoria de segurança dos MCP servers ativos. Complementa
`mcp-recommender` (sugestão) com foco em postura defensiva: o que JÁ está
conectado é seguro?

## Quando ativar

- Round cujo gap é da categoria `mcp_security`, `excessive_agency`,
  `supply_chain_ai`, ou qualquer ATK marcado como **`crit` ou `high`**
  envolvendo tool use externo / agent autonomy.
- Detectado: `~/.claude.json`, `~/.cursor/mcp.json`, ou config Claude
  Desktop contendo `mcpServers`.

⚠ **Prioridade alta** — MCP malicioso ou com escopo excessivo = RCE +
exfiltração silenciosa. Em empate, este agente vence o pick.

## Prompt

```
Target: ATK-{XXX} ({severity}) — {title}. Vector: {vec}.

Audit dos MCPs ativos:
1. Inventário: listar todo MCP em ~/.claude.json + configs Claude Desktop.
2. Whitelist check: cada MCP deve estar em mcp-catalog.yml com
   blindar_compatible:true. Não-listado = HIGH (review manual).
3. Capability bleed: MCP com nome contendo shell|exec|eval|sudo|admin →
   CRIT (escopo de RCE).
4. Token/secret hygiene: chave de API ou token no config em plain text
   → CRIT. Deve referenciar env var ou keychain.
5. Local binary: MCP local (command: ./path) sem hash/checksum
   documentado → MED.
6. Vendor clarity: MCP sem campo "version" + "vendor" identificável → LOW.
7. Update freshness: MCP sem release há >6m → LOW (deps potencialmente
   vulneráveis).
8. Excessive agency: MCP com scope write:* sem confirmation hook →
   HIGH (OWASP LLM08).

Implement minimal change closing the vector:
- Doc em .blindar/mcp-audit.md com inventário + classificação.
- Remoção/quarentena de MCPs não-whitelisted via PR ao operador.
- sec.html: matrix MCP-by-MCP, status verde/amarelo/vermelho.

Fail-closed: novos MCPs entram em "review" até operador aprovar.
```

## Princípios não-negociáveis

- **Nenhum MCP fora da whitelist roda sem review.** Catálogo é a fonte
  da verdade; tudo fora exige operador justificar e aprovar.
- **Tokens NUNCA em plain text no config.** Sempre `${env:VAR}` ou
  keychain reference. Detecção estática falha.
- **Capability bleed = banimento automático.** MCP com `shell`, `exec`,
  `eval`, `sudo`, `admin`, `system` no nome ou tools = CRIT, quarentena
  imediata.
- **Write scope exige confirmation hook.** MCP que pode escrever
  (`write:*`, `delete:*`, `execute:*`) sem mecanismo de confirmation
  per-call = HIGH.
- **Local binary sem checksum = supply chain risk.** Hash SHA256
  documentado no catálogo; mismatch = falha.
- **Inventário versionado.** `.blindar/mcp-audit.md` commit a cada
  scan; diff revela MCPs adicionados sem revisão.

## Teste obrigatório (≥3 asserts)

- Happy: catálogo whitelist + config com MCP whitelisted → pass
- Edge: MCP local com hash documentado e matching → pass
- Attack: MCP nomeado "shell-runner" no config → CRIT falha; token
  `sk-xxx` em plain text no config → CRIT falha; MCP community sem
  vendor identificável → LOW warn

## Locais de config auditados

| Plataforma | Path |
|---|---|
| Claude Code | `~/.claude.json` (chave `mcpServers`) |
| Claude Desktop (macOS) | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Claude Desktop (Windows) | `%APPDATA%/Claude/claude_desktop_config.json` |
| Cursor | `~/.cursor/mcp.json` |
| Projeto local | `./.mcp.json`, `./.cursor/mcp.json` |

## Anti-padrões detectados

```jsonc
// RUIM — token plain text
{
  "mcpServers": {
    "github": {
      "command": "mcp-server-github",
      "env": { "GITHUB_TOKEN": "ghp_abc123realtoken" }  // CRIT
    }
  }
}

// BOM — referencia env do shell
{
  "mcpServers": {
    "github": {
      "command": "mcp-server-github",
      "env": { "GITHUB_TOKEN": "${env:GITHUB_TOKEN}" }
    }
  }
}

// RUIM — MCP com nome de capability bleed
{
  "mcpServers": {
    "shell-exec": { "command": "/usr/local/bin/shell-mcp" }  // CRIT
  }
}

// RUIM — binary local sem hash documentado
{
  "mcpServers": {
    "my-custom": { "command": "/home/user/custom-mcp" }  // MED — no checksum
  }
}
```

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| OWASP LLM Top 10 | LLM05 (Supply Chain), LLM07 (Insecure Plugin Design), LLM08 (Excessive Agency) |
| NIST AI RMF | GOVERN-1.5, MANAGE-2.1 |
| MITRE ATLAS | AML.T0010 (ML Supply Chain Compromise) |
| ISO 42001 | A.7.4 (AI system components), A.10.3 (Third-party AI) |
