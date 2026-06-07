# Runbooks — fora do escopo de código

Estes são **templates de documentos** que o skill recomenda ao projeto
final criar em `docs/`. Não são executáveis nem agentes — são procedimentos
que dependem de pessoas, não de código.

Cobertos aqui (resposta às técnicas #4, #8, #9, #10 do baseline de TI que
não cabem em código):

| Tópico | Status | Por que não é código |
|---|---|---|
| Antivírus / EDR / endpoint protection | template | infra de servidor/laptop, não app |
| Segmentação física de rede | template | infra/SecOps |
| Treinamento de conscientização | template | RH/L&D |
| Pentest manual (red team) | template | atividade humana periódica |
| Resposta a incidente | template | processo organizacional |
| Rotação de chaves | template | parcialmente código, parcialmente processo |
| Política de patches OS | template | parcialmente código (CI), parcialmente sysadmin |

## Templates disponíveis

- [`antimalware.md`](antimalware.md) — política de antivírus/EDR e quando aplicar
- [`network-segmentation.md`](network-segmentation.md) — referência de
  segmentação (lógica em código + física fora)
- [`security-awareness.md`](security-awareness.md) — checklist de
  treinamento (mínimo viável)
- [`pentest-schedule.md`](pentest-schedule.md) — cadência de pentest manual
  + critérios de escopo

> Runbooks técnicos (`incident-response.md`, `key-rotation.md`,
> `supply-chain.md`) são **gerados pelo skill por projeto** durante a
> Fase 5/6. Esses sim viram arquivo no projeto-alvo, não no skill.

## Como o skill usa

Na Fase 5 (production checklist), o skill verifica se cada runbook
relevante existe no projeto-alvo. Se faltar, registra em `.accept-risk.md`
e segue (warn, não bloqueia).

Para frameworks que exigem documento (ISO 27001 A.6, NIST CSF GV/PR.AT),
esses runbooks são o que vai cobrir.
