# agent: compliance

Genérico — audit chain, retention, redaction. Funciona pra GDPR/CCPA/SOC2/etc.

Para Brasil / LGPD / ANPD, ver também
[`compliance-lgpd-br.md`](compliance-lgpd-br.md) (extende este).

## Quando ativar

Round cujo gap é da categoria `compliance`. Detectado quando há PII (email,
telefone, CPF, endereço, dados sensíveis) sem audit ou retention.

## Prompt

```
Audit PII flows:
- PII reads sem audit log
- PII writes sem retention policy
- Audit log não append-only
- Audit sem hash chain
- Export endpoints sem rate-limit

Implement (técnico — código):
1. Append-only audit + Merkle hash chain (prevHash + entryHash SHA-256)
2. Retention daemon (default 365d)
3. DSAR rate-limited
4. Redaction helpers

Test: verify_chain detecta mod/del/insert.
```

## Princípios

- **Audit log append-only**, jamais reescrito.
- **Hash chain Merkle** (`prevHash + entryHash` SHA-256) detecta
  modificação, deleção ou inserção retroativa.
- **Retention daemon** apaga/redacta registros expirados (default 365d).
- **DSAR endpoints rate-limited** (DSAR pode virar vetor de DoS).
- **Redaction helpers** centralizados (não dispersar regex pelo código).

## Teste obrigatório

`verify_chain()` detecta:
- modificação retroativa
- deleção de entrada
- inserção fora de ordem

Se algum desses passa, o hash chain está broken — round volta pra fila.
