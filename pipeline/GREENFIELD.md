---
phase: GREENFIELD
title: Modo GREENFIELD — projeto do zero até pronto para produção
duration_estimate: variável (horas)
output: projeto implementado + .blindar/ completo + gates da Fase 06b
entered_from: 00-mode-select.md
---

# Modo GREENFIELD — construir já blindado

O `blindar` padrão **audita o que existe**. Aqui não existe nada, então a
ordem inverte: em vez de encontrar problemas e corrigir, o objetivo é **não
criar o problema**.

> **Princípio**: é mais barato nascer com `tenant_id` do que adicionar depois.
> Cada decisão adiada em greenfield vira um round de hardening no futuro.

O ganho real do GREENFIELD é este: as ~95 regras que os checks determinísticos
verificam viram **requisitos de construção**, não achados de auditoria.

---

## Ordem obrigatória

Cada etapa é gate da seguinte. Não avance com a anterior em aberto.

### G1 — Requisitos (não gere código aqui)

Pergunte o que não dá para inferir. O `SETUP` do `CLAUDE.md` global do
operador já define o mínimo:

1. **Tipo** — Produção / MVP / Protótipo / Landing / E-com / API / Mobile / CLI / Lib
2. **Dados** — reais ou simulados? execução completa ou por fases?
3. **Inspirações visuais** — 3 referências (pular se não tem UI)

Além desses, o GREENFIELD precisa de:

4. **Usuários e papéis** — tem master? admin? usuário comum? convidado? conta
   de serviço? Não assuma que "admin" basta. Isto define o modelo de
   autorização inteiro e é caríssimo mudar depois.
5. **Multi-tenant?** — se sim, `tenant_id` entra em **toda** tabela desde a
   primeira migration, e o isolamento entra nos testes desde o primeiro.
6. **Dados pessoais?** — se sim, o ciclo de vida (retenção, exclusão,
   exportação, anonimização) é requisito, não item de compliance posterior.
7. **Processamento assíncrono?** — se sim, fila com retry e DLQ nascem juntas.
8. **IA/LLM?** — se sim, o provider entra atrás de uma porta (Ports & Adapters),
   nunca acoplado.

**NÃO gere código antes das respostas.**

### G2 — Arquitetura alvo

Produza, antes de qualquer arquivo:

- Stack escolhida e **por quê** (vai para o Decision Log).
- Fronteiras: o que é módulo, o que fala com o quê.
- Modelo de dados inicial.
- Modelo de autorização (papéis × recursos × ações).
- Ambientes: dev, test, produção — e a promessa de que serão **a mesma engine**.

Decisões desta etapa entram em `.blindar/decisions.md` com alternativas
consideradas. Elas serão questionadas mais tarde; sem registro, serão
questionadas do zero.

### G3 — Fundação de dados

**PostgreSQL é o default** quando o projeto precisa de banco relacional.

SQLite só entra com justificativa explícita e registrada — e nunca "por
enquanto, depois a gente migra". Esse "depois" é exatamente o custo que o modo
GREENFIELD existe para evitar.

Nascem juntos, nesta etapa:

- schema + primeira migration (reversível)
- `tenant_id` se multi-tenant
- `deleted_at` (soft delete) nas entidades principais
- índices das FKs
- **seed com dados simulados no banco** — nunca array hardcoded no código
- backup + procedimento de restore

### G4 — Backend

- Autenticação e autorização antes das rotas de negócio.
- Validação de entrada em toda borda.
- Try-catch em todo handler.
- Paginação obrigatória em toda listagem.
- Audit log nas ações sensíveis.
- Se há assíncrono: fila + worker + retry (3) + backoff + DLQ + idempotência.

### G5 — Frontend (se houver UI)

- Mobile-first, WCAG AA, alvos de toque ≥ 44×44px.
- Empty state com ícone + texto + CTA — tela vazia sem orientação é bug.
- Loading com skeleton, não spinner.
- Erro com mensagem acionável.
- Confirmação modal em ação destrutiva.
- **Nenhum botão sem handler real.** Nenhum "salvo!" que não salvou.

### G6 — IA / RAG (só se G1.8 = sim)

- Provider atrás de adapter.
- Prompt de sistema fora do código versionado como dado.
- Defesa contra prompt injection na borda.
- Se RAG: autorização **no retrieval**, não só na resposta. Documento que o
  usuário não pode ver não pode ser recuperado.
- Teto de custo e observabilidade de tokens desde o primeiro dia.

### G7 — Infraestrutura

- Docker + Compose desde o início, com a **mesma engine de banco** de produção.
- Healthcheck, restart policy, volumes persistentes.
- Secrets em env, nunca no código.
- `.gitignore` com `.env*`, `data/`, `uploads/`, `node_modules/`.

### G8 — Testes

Escritos junto com o código, não depois. Unit + integração + E2E do caminho
principal. Teste que valida comportamento real — não teste escrito para subir
cobertura.

### G9 — Observabilidade

Log estruturado, correlation ID, métricas de negócio, alerta no que importa.
Critério: **se quebrar às 3h, dá para descobrir o que aconteceu?**

### G10 — Documentação

README que permite a outra pessoa subir o projeto, ADRs das decisões de G2,
runbook de incidente.

---

## Fechamento — o GREENFIELD entrega ao HARDEN

Terminado G10, o projeto **deixa de ser greenfield**. Rode o pipeline padrão
(`00-launcher.md` → Fase 09) sobre o que foi construído.

Isto não é redundância. O GREENFIELD constrói com as regras em mente; o HARDEN
**verifica** com os mesmos checks determinísticos que rodariam em qualquer
projeto. Intenção não é evidência.

O critério de saída é o mesmo de todo mundo: os gates da Fase 06b.

---

## Anti-padrões deste modo

- ❌ SQLite "por enquanto" — é o custo que este modo existe para evitar.
- ❌ Mock/fake como implementação inicial "pra destravar" — vira permanente.
  Dado simulado vai no **banco**, via seed.
- ❌ Adiar autorização para "depois que as telas estiverem prontas".
- ❌ Adiar `tenant_id` em projeto multi-tenant.
- ❌ Gerar as 40 telas antes de provar que 1 fluxo funciona ponta a ponta.
- ❌ Pular o HARDEN final porque "acabou de ser feito, está limpo".
