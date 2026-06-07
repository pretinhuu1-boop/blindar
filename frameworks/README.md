# Frameworks — mapeamento de controles

Estes arquivos **NÃO são agentes** — não rodam loop. São tabelas de
referência que mapeiam controles de cada framework aos **agentes/ATKs**
do skill.

Uso:
- **Fase 1 (Discovery)**: se o projeto declara perseguir certificação
  específica, o discovery marca os controles do framework como categorias
  extras na matrix do `sec.html`.
- **Fase 5 (Production checklist)**: para projetos com certificação alvo,
  gera relatório de coverage por framework.

## Frameworks cobertos

| Framework | Aplicabilidade | Status |
|---|---|---|
| [`iso-27001.md`](iso-27001.md) | Geral, certificação corporativa | mapeado |
| [`nist-csf.md`](nist-csf.md) | Geral, operacional/estratégico + família SP 800 | mapeado |
| [`cis-controls.md`](cis-controls.md) | Prático, ataques comuns | mapeado |
| [`owasp-asvs.md`](owasp-asvs.md) | **Verificação de aplicação** — régua dos rounds | mapeado |
| [`pci-dss.md`](pci-dss.md) | Processadores de cartão (**condicional**) | mapeado |
| [`soc2.md`](soc2.md) | SaaS / cloud / B2B | mapeado |
| [`cobit.md`](cobit.md) | Governança corporativa | **stub** (baixa aplicabilidade em código) |

## Outras referências citadas

Não viraram arquivo próprio (não justificam) mas são citadas onde
relevante:

| Referência | Tipo | Onde aparece |
|---|---|---|
| **PTES** (Pentest Execution Standard) | Metodologia pentest | [`agents/pentest.md`](../agents/pentest.md), [`runbooks/pentest-schedule.md`](../runbooks/pentest-schedule.md) |
| **OWASP WSTG** | Guia testes web | [`agents/pentest.md`](../agents/pentest.md) |
| **NIST SP 800-115** | Guia técnico pentest | [`agents/pentest.md`](../agents/pentest.md) + [`nist-csf.md`](nist-csf.md) |
| **OSSTMM** | Teste operacional (90% fora de código) | [`agents/pentest.md`](../agents/pentest.md) (subset) |
| **CREST** | Conduta de firma pentest | [`agents/pentest.md`](../agents/pentest.md) + [`runbooks/pentest-schedule.md`](../runbooks/pentest-schedule.md) |
| **SANS** | Organização de treinamento | [`runbooks/security-awareness.md`](../runbooks/security-awareness.md) (fonte de material) |
| **ANSI** | Coordenação de padrões | Não citado — endossa ISO/IEC já mapeados |
| **OSINT** | Disciplina de reconhecimento | ❌ **Não coberto** — blindar é defesa, não reconhecimento |

## Mais aceito internacionalmente

**ISO/IEC 27001** é o padrão mais reconhecido globalmente para gestão de
segurança da informação. **NIST CSF** é o mais usado como guia
operacional/estratégico (inclusive fora dos EUA).

Para a maioria dos projetos: cobrir ISO 27001 + NIST CSF cobre 80-90% do
que outros frameworks pedem.

## Como o skill usa isso

Cada agente em `agents/` tem ao final uma seção **"Mapeamento de
frameworks"** com tabela do tipo:

| Framework | Controle |
|---|---|
| ISO 27001 | A.9.1.x |
| NIST CSF | PR.AC-1 |
| ... | ... |

Isso permite, ao fim do ciclo, gerar coverage report por framework
sem implementar nada framework-específico.
