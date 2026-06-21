# blindar

> Audit, harden and prepare projects for production with a deterministic + AI-powered pipeline.

**blindar** is a Claude Code skill (and standalone CLI) that:

1. Asks 4 questions about your project (type, sensitivity, rigor, framework)
2. Lets you pick which of 15 modules to run (or sensible defaults)
3. Runs ~72 specialized agents covering security, performance, a11y, compliance, DX, tests
4. Outputs a release decision (GO / CONDITIONAL GO / NO-GO) with criticals + highs + mediums
5. Optionally auto-fixes common findings
6. Generates client-facing report (HTML)

## Install (CLI)

```bash
npm install -g @blindar/cli
# or
npx @blindar/cli check
```

## Install (Claude Code skill)

```bash
git clone https://github.com/pretinhuu1-boop/blindar.git ~/.claude/skills/blindar
```

Then in any Claude Code session:

```
/blindar
```

## Quick start

```bash
cd your-project
npx blindar init          # creates .blindar/config.yml
npx blindar check         # runs deterministic checks
npx blindar check --apply # auto-fixes safe issues
npx blindar terminate     # release decision (exit 0=GO, 4=NO-GO)
npx blindar report        # generates HTML report
```

## GitHub Action

```yaml
- uses: pretinhuu1-boop/blindar@v0.31
  with:
    mode: ci
    fail-on: crit,high
    post-comment: true
```

## Philosophy

- **Deterministic first, AI second.** Shell scripts catch what they can; agents handle nuance.
- **No mocks, no broken UIs, no fake "saved!" toasts.** Honesty over demo polish.
- **Tenant isolation is not optional in multi-tenant.** Tested, not assumed.
- **Secrets rotate. Hard delete kills entities. Logs leak.** Defaults that protect.

## Modules (15)

| # | Name | When |
|---|---|---|
| 1 | Baseline & Discovery | always |
| 2 | Core security (auth, crypto, AI safety, file uploads, tenant) | always |
| 3 | Frontend hardening (CSP/XSS/Trusted Types) | UI detected |
| 4 | Network & API (payments, realtime, gateway, GraphQL, gRPC) | SaaS/ecom/API |
| 5 | Supply chain + SBOM/SLSA | always |
| 6 | Observability + cost monitoring | SaaS/ecom/API |
| 7 | DB + Backup + multi-region + ETL | DB detected |
| 8 | Compliance (LGPD/GDPR/HIPAA/PCI) | sensitive data |
| 9 | Performance backend + Redis + CDN | SaaS/ecom/API |
| 10 | Frontend fluidity + SEO + PWA + a11y + i18n + mobile + analytics + media | UI detected |
| 11 | E2E tests + visual regression | always |
| 12 | Anti-mock + config externalization + content quality | always |
| 13 | Resilience + scalability + chaos + event-driven | production rigor |
| 14 | DX + flags + email + docs + reports + MCP recommender | always |
| 15 | Pentest + adversarial review | always |

## License

MIT — see [LICENSE](../../LICENSE).
