---
name: regulatory-mapper
category: vertical
module: 8
priority: P1
description: |
  Mapeia normas/leis/NRs/regras que fazem sentido para ESTE projeto (setor +
  dados + geografia) e o que precisa seguir. Não despeja tudo — só o aplicável.
---

# Agent: regulatory-mapper

## Missão

Cada projeto tem um conjunto próprio de obrigações regulatórias, e cumprir a
errada (ou ignorar a certa) é caro. Este agente olha o domínio, os dados
manipulados e a geografia e **lista o que se aplica** + o requisito concreto —
em vez de jogar todos os frameworks de uma vez.

Complementa os agentes de compliance específicos (LGPD, GDPR, HIPAA, PCI): o
mapper decide QUAIS deles fazem sentido acionar.

## Procedimento (API-wrapped)

`check-regulatory-mapper.api.sh` coleta README + manifests + sinais de domínio
(cpf/pix/cartão/saúde/fhir/menor/biometria…) via grep e chama a Claude API.
Requer `ANTHROPIC_API_KEY` (skip gracioso sem ela).

## Cobertura (quando aplicável aos sinais)

- **Dados pessoais BR**: LGPD + ANPD; dados de criança/adolescente (ECA + foco de
  fiscalização ANPD 2026); base legal, retenção, DPO, RIPD; breach em 3 dias úteis.
- **Global**: GDPR, CCPA; SCC obrigatória em transferência internacional.
- **Pagamentos**: PCI-DSS; open finance/BACEN.
- **Saúde**: HIPAA, FHIR/HL7; dado sensível de saúde na LGPD.
- **Acessibilidade**: WCAG 2.2 AA; eMAG/LBI se gov/BR.
- **Trabalho/segurança física**: NRs (NR-1 GRO, NR-17 ergonomia de telas).
- **Setoriais**: Marco Civil da Internet.

## Output esperado

Findings: `severity` (risco de não cumprir), `message` (norma + nexo com o
projeto), `fix` (requisito a seguir). Alimenta o módulo 8 (compliance).

## Anti-padrões

- ❌ Listar norma sem nexo com o projeto ("por garantia").
- ❌ Afirmar aplicabilidade sobre sinal ambíguo — diga o que confirmar.
- ❌ Tratar conformidade como checkbox — cada requisito tem uma ação concreta.
