# agent: cryptography

Criptografia em trânsito, em repouso, e gestão de segredos. Cobre técnica #2
do baseline.

## Quando ativar

Round cujo gap envolve:
- Dados sensíveis sem cifra (PII, financeiro, saúde)
- Comunicação sem TLS / TLS fraca
- Secrets em plaintext (env, código, logs)
- Crypto custom (red flag)

⚠ **Prioridade alta** — security-first.

## Prompt

```
Target: ATK-{XXX} ({severity}) — {title}.

Audit crypto:
1. TLS: versão mínima 1.2 (ideal 1.3), HSTS habilitado, sem cipher fraco.
2. At-rest: DB cifrado (TDE ou app-level field encryption pra PII),
   backups cifrados, discos cifrados em infra.
3. Secrets: nenhum em código/git/log. Usar vault (HashiCorp, AWS Secrets
   Manager, GCP Secret Manager) ou env var injetada por orquestrador.
4. Algos: SHA-256+ pra integridade, AES-256-GCM pra cifra simétrica,
   Argon2id pra senha. PROIBIDO: MD5, SHA-1, DES, RC4, ECB mode,
   crypto custom.
5. Key management: rotação documentada, KEK ≠ DEK, revogação testada.
6. PRNG: secrets.token_bytes / crypto.randomBytes — NUNCA Math.random().

Implement minimal change (≤80 LOC):
- Teste prova que dado é ilegível sem chave.
- Grep estático: falha em MD5/SHA1/Math.random em path crítico.
- sec.html: ATK → covered.
- Atualiza docs/key-rotation.md.

Crypto agility: bumpar algo é troca de constante + migration, não
reescrita.
```

## Princípios não-negociáveis

- **"Don't roll your own crypto"** — usa libs estabelecidas (libsodium,
  cryptography.io, Web Crypto API). Crypto custom = round rejeitado.
- **TLS 1.2 mínimo, 1.3 preferido.** Sem TLS = sem prod.
- **Secrets nunca em código.** Grep estático falha se aparecer chave que
  parece API key (regex de gitleaks).
- **Rotação de chave testada.** Runbook `docs/key-rotation.md` existe e
  exercício de rotação roda em staging trimestralmente.
- **PRNG forte sempre.** `Math.random()` em path de auth/token = bug crítico.
- **PII em log = bug crítico.** Helper de redaction centralizado.

## Teste obrigatório

- Happy: cifra + decifra com chave correta funciona
- Edge: chave errada → erro (não silenciosamente retorna lixo)
- Attack: dump do storage cru não revela plaintext

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| ISO 27001 | A.10.1.x (Cryptographic controls) |
| NIST CSF | PR.DS-1 (at-rest), PR.DS-2 (in-transit) |
| CIS Controls | Control 3 (Data protection) |
| PCI-DSS | Req 3 (stored data), Req 4 (transmission) |
| SOC 2 | CC6.7 |
