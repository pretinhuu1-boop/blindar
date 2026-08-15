# Decisões

## 0001 — Usar PostgreSQL em vez de SQLite

### Contexto
O sistema precisa de escrita concorrente e de tipos de data com timezone.

### Alternativas
- SQLite: simples, mas serializa escrita e não aplica FK por default.
- MySQL: adequado, mas a equipe não tem operação dele.

### Decisão
PostgreSQL 16 em container, mesma engine em dev, test e produção.

### Consequências
Exige container em dev. Ganha checagem de FK real e TIMESTAMPTZ.
