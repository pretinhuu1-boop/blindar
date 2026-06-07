# Adaptação por stack

Discovery agent (Fase 1) identifica stack e adiciona categorias relevantes
na matrix do `sec.html`.

| Stack | Categorias extras |
|---|---|
| Python + Postgres | `pool_isolation`, `sqli_via_orm` |
| Node + Express | `event_loop_block`, `prototype_pollution` |
| Go | `goroutine_leak`, `channel_deadlock` |
| Rust | `unsafe_block_audit` |
| SPA (qualquer) | `csp`, `trusted_types`, `sw` (Service Worker) |
| Mobile (iOS/Android) | `ssl_pinning`, `root_detection` |

## Como expandir

Quando um stack novo aparecer:

1. Identifique 2-3 ATKs específicos da stack que já mordeu em produção
   (princípio: nada entra aqui sem bug real observado).
2. Adicione linha na tabela acima.
3. Bump `VERSION` minor + `CHANGELOG.md`.

## Casos limítrofes

- **Monorepos multi-stack**: discovery roda por subprojeto, matrix do
  `sec.html` ganha sufixo por package.
- **Stack obscura sem entrada aqui**: o skill ainda funciona com as
  categorias genéricas (`web_api`, `auth_session`, etc.). Não bloqueia,
  só perde adaptação fina.
