# Frameworks, templates, runbooks, stacks e tendências

> Referência do `blindar`, extraída do `SKILL.md` para não ocupar o
> caminho quente. Carregue quando a etapa exigir.

## Frameworks de referência


Mapeamento de controles, **não agentes**:

| Framework | Quando usar |
|---|---|
| [`frameworks/iso-27001.md`](../frameworks/iso-27001.md) | Certificação corporativa, mais aceito globalmente |
| [`frameworks/nist-csf.md`](../frameworks/nist-csf.md) | Operacional/estratégico + família SP 800 |
| [`frameworks/cis-controls.md`](../frameworks/cis-controls.md) | Mais acionável; bom pra começar |
| [`frameworks/owasp-asvs.md`](../frameworks/owasp-asvs.md) | **Régua de verificação por requisito** — L1/L2/L3 |
| [`frameworks/pci-dss.md`](../frameworks/pci-dss.md) | Condicional — só processadores de cartão |
| [`frameworks/soc2.md`](../frameworks/soc2.md) | SaaS / cloud / B2B |
| [`frameworks/cobit.md`](../frameworks/cobit.md) | ⚠ stub — governança corporativa (pouco em código) |

Metodologias de pentest (PTES, OWASP WSTG, NIST SP 800-115, OSSTMM, CREST)
estão referenciadas em [`agents/pentest.md`](../agents/pentest.md), não em
arquivos separados — todas tratam de **como testar**, não **o que
implementar**.

Discovery (Fase 2) detecta se projeto declara um framework alvo
(`.compliance-target`, `README`, `package.json`) e gera coverage report
no relatório final (Fase 6).

## Templates


- [`templates/sec.html`](../templates/sec.html) — dashboard single-file
- [`templates/execution-report.html`](../templates/execution-report.html) — relatório técnico cumulativo
- [`templates/client-report.html`](../templates/client-report.html) — relatório do cliente
- [`templates/frontend-preview.html`](../templates/frontend-preview.html) ⭐ v0.20 — preview/aprovação de frontend
- [`templates/accept-risk.md`](../templates/accept-risk.md) — riscos aceitos
- [`templates/role-hierarchy.md`](../templates/role-hierarchy.md) — template de roles
- [`templates/pr-message.md`](../templates/pr-message.md) — formato de PR

## Runbooks (fora de código, para projetos-alvo)


- [`runbooks/antimalware.md`](../runbooks/antimalware.md) — EDR/AV (infra)
- [`runbooks/network-segmentation.md`](../runbooks/network-segmentation.md) — físico
- [`runbooks/security-awareness.md`](../runbooks/security-awareness.md) — treinamento
- [`runbooks/pentest-schedule.md`](../runbooks/pentest-schedule.md) — pentest humano

Esses arquivos cobrem o que ISO 27001 / NIST CSF exigem mas que **não cabe
em PR**: antivírus em laptop, treinamento de RH, pentest manual humano.

## Adaptação por stack


[`stacks.md`](../stacks.md) — categorias extras por stack (Python/Node/Go/Rust/SPA/Mobile).

## Tendências 2026 (curadoria semestral)


[`docs/trends-2026.md`](../docs/trends-2026.md) — React Compiler v1, RSC default,
Edge runtime, performance budget 400KB, headers HTTP, supply chain SHA-pin,
ANPD 2026 (crianças/IA/scraping/SCC/breach 3d). Agentes relevantes consultam
ao rodar.
