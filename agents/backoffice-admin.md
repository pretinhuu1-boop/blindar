---
name: backoffice-admin
category: devops
module: 14
priority: P2
description: |
  Backoffice/admin tools como feature de primeira classe (não rota
  escondida sem auth). Cobre: impersonation auditada (entrar como user
  pra suporte sem saber a senha), audit dashboards, support workflows
  (refund, conta bloqueada, dados exportados), data exports LGPD/GDPR,
  ferramentas de moderação. Reduz tempo de resolver ticket de horas pra
  minutos.
---

# Agent: backoffice-admin

## Missão

App em produção precisa de ferramentas internas pra suporte, finanças,
moderação e auditoria. Sem isso, qualquer ticket vira "vou ver no banco"
(arriscado) ou "preciso de uma feature pra X" (lento). Backoffice bem feito
= operação rápida e segura.

## Quando rodar

- Módulo 14 selecionado
- Tipo do projeto ∈ {saas, ecom} com usuários pagantes
- Operador pediu "admin", "support", "backoffice", "impersonation"

## A. Impersonation (entrar como user)

### Por que: suporte precisa reproduzir o que user vê. Senha NUNCA pode ser
pedida ("qual é sua senha?") — é red flag de phishing e quebra LGPD.

### Fluxo seguro

```
1. ADMIN/MASTER autenticado entra em /admin/users/[id]
2. Clica "Impersonar"
3. UI pede motivo OBRIGATÓRIO (texto livre)
4. Backend valida: MASTER role + audit log com motivo + IP + timestamp
5. Backend emite token especial:
   - sub = userId (impersonado)
   - act = adminId (actor real)
   - impersonation = true
   - exp = 30min (curto)
6. Frontend mostra banner persistente: "Você está como Maria. Sair"
7. TODAS as ações logam (actorId=admin, asUserId=user)
8. Ações ESCRITAS exigem confirmação extra OU são bloqueadas
9. Logout especial volta pra sessão do admin (não dropa ambas)
```

### Implementação

```ts
@Post('admin/users/:id/impersonate')
@Roles('MASTER')   // só MASTER, não ADMIN
async impersonate(@Param('id') userId, @Body() { reason }, @Req() req) {
  if (!reason || reason.length < 10) throw new BadRequest('motivo obrigatório, ≥ 10 chars');

  const target = await db.user.findUnique({ where: { id: userId } });
  if (!target) throw new NotFound();
  if (target.role === 'MASTER') throw new Forbidden('não impersonar MASTER');

  const token = signJWT({
    sub: userId,
    act: req.user.id,
    impersonation: true,
    role: target.role,
    tenantId: target.tenantId
  }, { expiresIn: '30m' });

  await audit.log({
    type: 'impersonation_start',
    actorId: req.user.id,
    targetId: userId,
    reason,
    ip: req.ip,
    userAgent: req.headers['user-agent']
  });

  return { token };
}
```

### Banner UI persistente

```tsx
{user.impersonation && (
  <Banner variant="warning" sticky>
    <Icon>⚠️</Icon>
    Você está como <strong>{user.name}</strong> (impersonação por suporte)
    <Button onClick={endImpersonation}>Voltar pra mim</Button>
  </Banner>
)}
```

## B. Ações destrutivas em impersonation

```ts
const DESTRUCTIVE = ['delete_account', 'change_email', 'change_password', 'transfer_money'];

if (req.user.impersonation && DESTRUCTIVE.includes(action)) {
  throw new Forbidden('Ação destrutiva bloqueada em modo impersonação');
}
```

Suporte vê tudo, mas não pode **agir como** o user em ação séria.

## C. Audit dashboard

```
┌──────────────────────────────────────────────────────────────┐
│ Audit Log                          [Filtros] [Export CSV]    │
├──────────────────────────────────────────────────────────────┤
│ when              actor          action            target    │
│ 14/06 14:32  Maria (MASTER)  impersonation_start  José       │
│ 14/06 14:35  Maria→José      appointment_view     APT-123    │
│ 14/06 14:36  Maria→José      appointment_edit     APT-123    │
│ 14/06 14:40  Maria (MASTER)  impersonation_end    José       │
├──────────────────────────────────────────────────────────────┤
│ Filtros: actor, target, tenant, action, periodo              │
│ Total: 47.234 eventos no período                              │
└──────────────────────────────────────────────────────────────┘
```

### Schema

```sql
CREATE TABLE audit_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  actor_id     UUID NOT NULL,
  actor_role   TEXT NOT NULL,
  acting_as    UUID,                -- se impersonation, quem é o user "visível"
  tenant_id    UUID,
  type         TEXT NOT NULL,
  target_type  TEXT,
  target_id    UUID,
  changes      JSONB,
  reason       TEXT,
  ip           INET,
  user_agent   TEXT,
  request_id   TEXT,
  at           TIMESTAMPTZ NOT NULL DEFAULT now()
) PARTITION BY RANGE (at);

-- Particionamento mensal (mantém perf em tabela grande)
CREATE TABLE audit_log_2026_06 PARTITION OF audit_log
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE INDEX idx_audit_actor ON audit_log(actor_id, at DESC);
CREATE INDEX idx_audit_target ON audit_log(target_type, target_id, at DESC);
CREATE INDEX idx_audit_tenant ON audit_log(tenant_id, at DESC);
```

## D. Support workflows

### Conta bloqueada / suspeita

```
1. Ver últimas 30 ações do user
2. Ver dispositivos logados (sessões ativas)
3. Forçar logout de todos os devices (revoga refresh tokens)
4. Bloquear/desbloquear conta com motivo
5. Forçar troca de senha no próximo login
6. Notificar user por email com link de recuperação
```

### Refund / chargeback

```ts
// Tool dedicado, não SQL direto
@Post('admin/refunds')
@Roles('ADMIN','MASTER')
async refund(@Body() { paymentId, amount, reason }, @Req() req) {
  await audit.log({ type: 'refund_attempt', actorId: req.user.id, /* ... */ });
  // chama gateway
  // marca payment.status = 'refunded'
  // notifica user
}
```

NUNCA refund via SQL update direto. Workflow audita + integra gateway.

### LGPD export / deletion

```ts
@Post('admin/lgpd/export/:userId')
@Roles('ADMIN','MASTER')
async exportUserData(@Param('userId') id, @Req() req) {
  // Coleta TODOS dados pessoais do user
  const data = await collectUserPII(id);

  // Gera ZIP com JSON estruturado + arquivos
  const zip = await packageExport(data);

  // Upload em storage com URL pré-assinada expirando em 24h
  const url = await uploadAndSign(zip, '24h');

  // Audit + notifica user
  await audit.log({ type: 'lgpd_export', /* ... */ });
  await email.send(user.email, 'Seus dados estão prontos', { url });
}
```

```ts
@Post('admin/lgpd/delete/:userId')
@Roles('MASTER')   // só MASTER (impacto alto)
async deleteUser(@Param('userId') id, @Body() { reason }) {
  // Anonimiza (não deleta físico — audit precisa do registro)
  await anonymizeUser(id, reason);
  // Audit + notifica user antes (LGPD Art. 18 IV)
}
```

## E. Moderação (se app tem UGC)

- Reportar conteúdo / usuário
- Fila de moderação
- Take-down de conteúdo (preserva original em archive)
- Ban temporário / permanente
- Shadow ban (visível só pro próprio user — anti-spam)

## F. Métricas operacionais (dashboards)

| Dashboard | Métrica |
|---|---|
| Health | uptime, error rate, p95 latency, requests/min |
| Business | DAU/MAU, conversão, ARPU, churn |
| Support | tickets abertos, tempo de resolução, top 10 motivos |
| Security | tentativas de login falhas, refresh reuse detection, audit anomalias |
| Cost | $ por tenant, $ por user, top features caras |
| Activation | % users que atingem aha em 24h, drop-off por step |

## G. Read-only DB access pra debug

```ts
// Conexão dedicada read-only pra admin queries ad-hoc
const adminReadDb = new PrismaClient({
  datasources: { db: { url: process.env.READ_REPLICA_URL } }
});

// Em rota admin SAFE — só SELECT, com timeout
@Post('admin/query')
@Roles('MASTER')
async queryReadonly(@Body() { sql }, @Req() req) {
  // Valida que é SELECT (parsing AST, não regex)
  if (!isReadOnlySQL(sql)) throw new Forbidden();

  // Timeout curto
  const result = await adminReadDb.$queryRawUnsafe(`SET LOCAL statement_timeout = '5s'; ${sql}`);

  // Audit OBRIGATÓRIO
  await audit.log({ type: 'admin_query', actorId: req.user.id, sql, rowCount: result.length });
  return result;
}
```

Reduz dependência de DBA / acesso direto ao DB. Tudo logado.

## H. Auth obrigatório para admin (não rota escondida)

```ts
// RUIM
app.get('/secret-admin', (req, res) => { ... });   // sem auth

// BOM
app.get('/admin/*',
  jwtAuthGuard,
  rolesGuard('ADMIN', 'MASTER'),
  ipAllowlistGuard,                  // só IPs da VPN?
  mfaRequiredGuard,                  // 2FA pra admin (sempre)
  auditMiddleware,                   // loga tudo
  ...
);
```

### MFA mandatório pra ADMIN/MASTER

WebAuthn ou TOTP. Senha sozinha NÃO basta pra admin.

## Output esperado em sec.html

```
┌─ Backoffice / Admin (Módulo 14) ─────────────────────────┐
│ Impersonation auditada        : ✅ + motivo obrigatório   │
│ Banner UI persistente         : ✅                         │
│ Ações destrutivas bloqueadas  : ✅ em impersonation       │
│ Audit log particionado        : ✅                         │
│ Support workflows             : ✅ refund/block/unblock   │
│ LGPD export + delete          : ✅                         │
│ Métricas operacionais         : 6 dashboards ✅           │
│ MFA pra ADMIN/MASTER          : ✅ WebAuthn               │
│ IP allowlist (opcional)       : ✅ VPN                    │
│ Read-only DB query (audit)    : ✅                         │
│ Status                        : ✅ OPERATIONAL            │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões (alguns CRIT)

- ❌ Rota admin sem auth ("secret URL")
- ❌ Pedir senha do user pra "ajudar" (phishing-shaped)
- ❌ Suporte conectando direto no DB de prod (vai dropar tabela)
- ❌ Refund via SQL update sem audit
- ❌ Impersonation sem motivo logado
- ❌ Impersonation que age igual ao user em ações destrutivas
- ❌ Banner "está como X" que some (user esquece e age "como" outra pessoa)
- ❌ Sem MFA pra admin (senha sozinha = elevation trivial)
- ❌ Sem rate limit em rotas admin (atacante força brute)
- ❌ LGPD delete físico (audit perde rastro)
- ❌ Admin queries direto no DB primary (race com produção)
