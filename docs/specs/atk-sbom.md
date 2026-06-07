# Spec: ATK SBOM (item #17 do ROADMAP)

> Software Bill of Materials de **defesas**: qual ATK fechou em qual PR,
> em qual versão do skill, com qual agente.

## Problema

Hoje, `sec.html` mostra estado FINAL. Mas auditor pergunta: "como você
sabe que ATK-027 foi de fato resolvido em 2026-09-15?" Precisa cavar
git log.

## Solução

`.blindar/sbom.json` mantido ao longo do ciclo (e exportado no
evidence-package):

```json
{
  "$schema": "../schemas/sbom.schema.json",
  "version": 1,
  "atks": [
    {
      "id": "ATK-027",
      "title": "Idempotency-Key missing in /api/charge",
      "category": "business_logic",
      "severity": "crit",
      "covered_at": "2026-09-15T11:23:00Z",
      "covered_by": {
        "pr": 142,
        "commit": "abc1234",
        "agent": "business-logic",
        "blindar_version": "0.5.0",
        "round_n": 18
      },
      "tests_added": [
        "tests/test_red027.py"
      ],
      "guards_added": [
        "scripts/grep-guard-idempotency.sh"
      ],
      "frameworks": [
        "OWASP ASVS V11.1.5",
        "ISO 27001 A.8.26"
      ],
      "verified_by_adversarial": true,
      "adversarial_round_n": 20
    }
  ]
}
```

## Eventos que atualizam SBOM

- Round mergeado (Fase 3) → adiciona entry
- Adversarial review (Fase 4) → marca `verified_by_adversarial`
- Drift detection (Fase 8) → flag `regressed_at` se defesa removida
- Risk acceptance → flag `accepted_risk` se ATK migra pra
  `accept-risk.md`

## Schema (futuro `schemas/sbom.schema.json`)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "blindar SBOM",
  "type": "object",
  "required": ["version", "atks"],
  "properties": {
    "version": { "type": "number" },
    "atks": {
      "type": "array",
      "items": { "$ref": "#/definitions/atk_entry" }
    }
  },
  "definitions": {
    "atk_entry": {
      "type": "object",
      "required": ["id", "category", "severity"],
      "properties": {
        "id": { "type": "string", "pattern": "^ATK-" },
        "title": { "type": "string" },
        "category": { "type": "string" },
        "severity": { "enum": ["crit", "high", "med", "low"] },
        "covered_at": { "type": "string", "format": "date-time" },
        "covered_by": {
          "type": "object",
          "properties": {
            "pr": { "type": "number" },
            "commit": { "type": "string" },
            "agent": { "type": "string" },
            "blindar_version": { "type": "string" },
            "round_n": { "type": "number" }
          }
        },
        "tests_added": { "type": "array", "items": { "type": "string" } },
        "guards_added": { "type": "array", "items": { "type": "string" } },
        "frameworks": { "type": "array", "items": { "type": "string" } },
        "verified_by_adversarial": { "type": "boolean" },
        "adversarial_round_n": { "type": ["number", "null"] },
        "regressed_at": { "type": ["string", "null"], "format": "date-time" },
        "accepted_risk": { "type": "boolean" }
      }
    }
  }
}
```

## Diferença vs `sec.html`

| Aspecto | `sec.html` | `sbom.json` |
|---|---|---|
| Audiência | humano olhando agora | auditor olhando depois |
| Formato | HTML dashboard | JSON estruturado |
| Histórico | snapshot atual | append-only |
| Versionável | sim (mas pesado) | sim (diff legível) |
| Assinável | só hash do arquivo | hash + per-entry |

## Por que não está implementado

Skill ainda **não atualiza estruturado durante rounds** — depende da AI
escrever no `sec.html` que é HTML+JS arrays. Migrar pra SBOM JSON
estruturado primeiro, depois renderizar HTML a partir dele, é refactor
significativo.

## Implementação proposta

Fase 1: cada round, AI também escreve em `.blindar/sbom.json` além de
`sec.html`.
Fase 2: `sec.html` lê de `sbom.json` em vez de hardcode (template muda).
Fase 3: validação de SBOM antes de cada PR.
