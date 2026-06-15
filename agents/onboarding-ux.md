---
name: onboarding-ux
category: frontend
module: 10
priority: P1
description: |
  Primeiros 5 minutos do usuário decidem retenção. Cobre: signup curto,
  empty states ricos (não tela branca), tour guiado contextual (não modal
  invasivo), activation funnel mensurável, demo data opcional, primeiro
  "aha moment" em ≤ 60s. Sem isso, MVP morre na primeira tela vazia.
---

# Agent: onboarding-ux

## Missão

A maioria das apps perde 50%+ dos usuários no primeiro acesso por:
1. Signup chato (10 campos antes de mostrar valor)
2. Tela vazia hostil (nenhuma direção)
3. Demo overwhelming (modal de tour com 12 slides)

Este agente garante que o primeiro acesso é **convidativo, curto e
direcionado** ao "aha moment".

## Quando rodar

- Módulo 10 selecionado
- Tipo de projeto ∈ {saas, ecom, landing}
- Operador pediu "onboarding", "primeira tela", "ativação"

## A. Signup mínimo

### Regras

- **3 campos no máximo** no signup inicial (email + senha + nome) OU
  social login (Google/Apple/Microsoft)
- **Sem confirmação de senha** (mostrar com botão "olho")
- **Perguntas restantes** depois de logado, espalhadas no fluxo natural
- **Email verification não-bloqueante** — deixa entrar, marca não-verificado,
  pede em momentos específicos (ações que precisam)
- **Passkey/biometria** oferecida no segundo login (não no primeiro — atrito)

```tsx
// Signup mínimo
<form>
  <Input name="email" type="email" autoComplete="email" required />
  <Input name="password" type="password" autoComplete="new-password" required
         minLength={12} />
  <Button>Criar conta</Button>
  <Divider>ou</Divider>
  <SocialButton provider="google">Continuar com Google</SocialButton>
  <SocialButton provider="apple">Continuar com Apple</SocialButton>
</form>
```

### Verificação de email

- Magic link (sem senha) > verificação por código
- Código de 6 dígitos > link em apps mobile (browser handoff)
- Reenviar em 30s, máx 5x/hora

## B. Empty states ricos

### Anti-pattern: tela em branco com "Sem dados"

### Pattern: ícone + título + descrição + CTA + (opcional) demo

```tsx
<EmptyState
  icon={<CalendarIcon />}
  title="Nenhum agendamento ainda"
  description="Você pode criar um agendamento manual ou compartilhar o link público pra clientes agendarem online."
  primary={<Button onClick={create}>Criar agendamento</Button>}
  secondary={<Button variant="outline" onClick={shareLink}>Compartilhar link</Button>}
  tertiary={<Link href="/help/agenda">Como funciona</Link>}
/>
```

### Lista de empty states obrigatórios

- [ ] Dashboard primeira vez (nenhum dado ainda)
- [ ] Lista vazia (sem resultados na query inicial)
- [ ] Resultado de busca/filtro vazio (sugerir reset)
- [ ] Erro de carregamento (retry button)
- [ ] Sem permissão (CTA pra pedir acesso)
- [ ] Feature ainda não usada (explicar valor + CTA)
- [ ] Tabela vazia (linha "Adicionar primeiro item")
- [ ] Notificações vazias ("Você está em dia ✓")

## C. Tour guiado contextual (não modal de 12 slides)

### Padrão certo: **tooltip + spotlight** no elemento, **1 passo por vez**

Bib: `react-joyride`, `intro.js`, `Shepherd.js`, `Driver.js`.

```ts
const tour = [
  {
    target: '#nav-appointments',
    title: 'Veja sua agenda aqui',
    content: 'Lista de hoje, semana e mês. Clique pra começar.'
  },
  {
    target: '#btn-new',
    title: 'Crie agendamentos',
    content: 'Manual ou compartilhe o link público.'
  }
];
```

### Regras

- 3-5 passos NO MÁXIMO (não 12)
- Sempre com **botão "Pular"** visível
- Persistir em `users.onboarding_completed_at` (não repetir)
- Mostrar tour só quando user fez login E tem dados ZERO
- Não bloquear UI durante tour (overlay translúcido, deixar interagir)

## D. Demo data opcional

User pode escolher: começar zero OU carregar dados de exemplo (5 clientes,
10 agendamentos, 3 serviços, marcados como "demo — você pode excluir").

```sql
INSERT INTO clients (..., is_demo) VALUES (..., true);
-- Botão sempre visível: "Limpar dados de demonstração"
-- DELETE FROM ... WHERE is_demo = true AND tenant_id = ?;
```

Resultado: user entende a feature sem precisar criar dados primeiro.
Quando pronto, limpa em 1 clique.

## E. Activation funnel mensurável

Defina o "aha moment" — momento em que user **vê o valor da app**.

Exemplos:
- Salon Pro: criou primeiro agendamento E conectou WhatsApp
- E-com: configurou produto + recebeu primeiro pedido
- SaaS de tarefas: criou primeiro projeto + adicionou 3 tarefas

Tracking obrigatório (analytics):
- `signup_completed`
- `tour_started` / `tour_completed` / `tour_skipped`
- `first_action_X_completed` (por feature key)
- `aha_moment_reached` (timestamp + tempo desde signup)
- `activation_completed_24h` (boolean — virou retido?)

Métrica: % de users que atingem aha em ≤24h. Meta: > 40%.

## F. Wizard pra setup pesado (só se necessário)

Para apps que precisam de muita config inicial (e-com com produtos, SaaS B2B):

```tsx
<Wizard
  steps={[
    { id: 'company', title: 'Sua empresa', component: CompanyForm },
    { id: 'brand',   title: 'Identidade visual', component: BrandForm },
    { id: 'team',    title: 'Convide o time', component: TeamForm, optional: true },
    { id: 'done',    title: 'Pronto!', component: SuccessScreen }
  ]}
  saveProgress
  resumable
/>
```

Cada passo:
- Salva progresso automático (pode sair e voltar)
- Tem opção "Pular" (não bloquear)
- Mostra progresso (3/5 passos)
- Estima tempo restante ("2 min")

## G. Tooltips contextuais (just-in-time help)

```tsx
<HelpIcon
  content="Comissão padrão para profissionais. Pode ser sobrescrita por serviço."
  position="top"
/>
```

Dispara ao **hover** (não auto-open). Em mobile: tap, fecha em tap fora.

## H. Onboarding checklist persistente

```
┌──────────────────────────────────────┐
│ Comece com o Salon Pro     2/5 ✓     │
│                                       │
│ ✓ Criar conta                         │
│ ✓ Conectar WhatsApp                   │
│ ☐ Criar primeiro serviço              │
│ ☐ Adicionar profissional              │
│ ☐ Compartilhar link público           │
│                                       │
│ [ Esconder até depois ]               │
└──────────────────────────────────────┘
```

- Visível no dashboard até completo OU "esconder até depois"
- Cada item é clicável → leva direto pra ação
- Anima ao completar (dopamine)

## I. Email transacional do welcome

```
Assunto: Bem-vindo ao Salon Pro 🎉

Olá Maria!

Sua conta está pronta. Em 3 passos rápidos você está atendendo:

1. Conecte seu WhatsApp → [Conectar]
2. Cadastre seus serviços → [Cadastrar]
3. Compartilhe seu link → salonpro.com/r/sua-loja

Precisa de ajuda? Responda este email — leio pessoalmente.

[Nome do fundador / equipe]
```

Personal > marketing genérico.

## Output esperado em sec.html

```
┌─ Onboarding UX (Módulo 10) ──────────────────────────────┐
│ Signup ≤ 3 campos             : ✅                         │
│ Magic link / passkey opcional : ✅                         │
│ Empty states em rotas-chave   : ✅ 8/8                     │
│ Tour ≤ 5 passos + skip        : ✅                         │
│ Demo data opcional            : ✅ + limpar 1 clique       │
│ Activation funnel tracked     : ✅ aha_moment evento       │
│ Onboarding checklist          : ✅ dashboard               │
│ Welcome email personal        : ✅                         │
│ Tooltips contextuais          : ✅ não bloqueantes         │
│ Métrica: ativação 24h         : 47% (meta > 40%) ✅        │
│ Status                        : ✅ ONBOARDED              │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Signup com 10 campos antes de mostrar a app
- ❌ Modal de tour com 12 slides bloqueando UI
- ❌ Tela em branco com "Sem dados"
- ❌ Verificação de email bloqueante (pode esperar)
- ❌ Demo data sem botão "limpar"
- ❌ Welcome email genérico "Olá usuário"
- ❌ Tour que repete a cada login (uma vez é suficiente)
- ❌ Esconder feature até user descobrir sozinho
- ❌ "Tutorial" em vídeo de 8 minutos como primeira tela
- ❌ Empty state sem CTA (user fica perdido)
