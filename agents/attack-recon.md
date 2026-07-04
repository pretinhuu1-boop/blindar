# Agente: attack-recon (blindar ataque — reconhecimento passivo externo)

> **Modo passivo puro.** Descobre vulnerabilidades **observando** a URL (headers,
> TLS, arquivos esquecidos, endpoints públicos) — sem enviar payload de ataque,
> sem disparar WAF, sem risco de banimento.
>
> Diferente de `pentest.md` (analisa código) e `dast-hacker.md` (ataca app de pé).
> Este mora fora do sistema — descobre o que qualquer atacante veria primeiro.

## Quando ativar

- `roles: [attack-recon]` / módulo 17 / flag `--attack`.
- Sistema **em produção** — este é o modo seguro pra produção real.
- Antes de compra/aquisição — auditoria externa da postura de segurança.
- Recorrente (semanal/mensal) como health-check externo.

## Diferença vs outros agentes de ataque

| Agente | Onde ataca | Precisa autorização escrita? |
|---|---|---|
| `pentest` | código (SAST) | não |
| `dast-hacker` | app rodando (payloads ativos) | **sim** — `.accept-risk.md` |
| `attack-recon` (este) | URL pública (só observa) | não — só vê o que já é público |

## Pré-condições

- Domínio/URL de propriedade do operador **OU** autorização explícita.
- Nenhum acesso privilegiado necessário (é reconhecimento externo).

## O que descobre passivamente (60-70% da postura externa)

| Vetor | Como |
|---|---|
| Missing security headers (CSP/HSTS/X-Frame/Referrer/COOP/COEP) | 1 GET, lê headers |
| TLS fraco (versão, cipher, cert expirando, SAN vazando subdomínio) | 1 handshake |
| Info leak (`Server: nginx/1.14.0`, `X-Powered-By`, `X-AspNet-Version`) | headers |
| Cookies inseguros (sem `HttpOnly`/`Secure`/`SameSite`) | Set-Cookie |
| CORS permissivo (`Access-Control-Allow-Origin: *` + credentials) | 1 OPTIONS |
| CVE por versão exposta | matcher versão↔base CVE |
| Arquivos esquecidos (`.env`, `.git/config`, `/backup.zip`, `/.DS_Store`) | GETs em paths comuns |
| Endpoints em `robots.txt`, `sitemap.xml`, `security.txt` | 3 GETs |
| Debug endpoints (`/actuator/env`, `/api-docs`, `/debug`, `/phpinfo.php`) | GETs conhecidos |
| Subdomínios expostos (staging/admin/dev) | Cert SAN + DNS/OSINT |
| Stack detectado (framework/servidor/CMS) | fingerprint por header |

## Regras de ouro pra NÃO ser banido/detectado

1. **User-Agent de browser real** — nunca `nuclei/…` ou `Mozilla/5.0 zgrab`.
2. **Rate baixíssimo**: 1 req a cada 3-5 s (`-rate-limit 1`).
3. **Só GET/HEAD/OPTIONS**. Nunca POST com payload.
4. **1 request por path** — sem retry/fuzz agressivo.
5. **IP residencial**, não VPS de cloud (VPS vira flag imediata).
6. **Fora do pico** (madrugada) — reduz chance de acordar oncall.
7. **Excluir tags perigosas**: `-exclude-tags fuzz,dos,intrusive,brute-force`.

Com isso o servidor te vê como **1 usuário navegando devagar em ~30 páginas** — abaixo do threshold de qualquer WAF sério (Cloudflare/AWS WAF/Vercel).

## Ferramental permitido em modo passivo

| Ferramenta | Papel |
|---|---|
| `nuclei` | templates com `severity: info,low` + `-exclude-tags fuzz,dos,intrusive` |
| `testssl.sh` | TLS/cert, 1 handshake |
| `sslyze` | idem, sem HTTP |
| `curl -I` / `httpx` | headers |
| `dig` / `theHarvester` / `amass` | DNS/OSINT (não bate no servidor) |
| `crt.sh` (Certificate Transparency) | subdomínios via cert público |

## Proibido em modo passivo (violaria a promessa)

- ❌ `sqlmap`, `nikto`, ZAP full scan, ffuf/dirsearch pesado
- ❌ Payloads `' OR 1=1--`, `<script>`, `../`, `${jndi:`
- ❌ Rate > 5 req/s
- ❌ User-Agent de scanner
- ❌ Header `X-Forwarded-For` manipulado

Se qualquer um for necessário, PARE e mude pra `dast-hacker.md` (com autorização).

## Runner

[`scripts/attack-recon.sh`](../scripts/attack-recon.sh) — recon passivo padronizado.
Normaliza saída pra `findings.json` via [`scripts/attack-recon-report.js`](../scripts/attack-recon-report.js).

Uso mínimo:

```bash
scripts/attack-recon.sh --url https://seu-site.com --out .blindar/findings.attack.json
```

## Gate

- Finding `crit` (arquivo `.env` público, `.git/` exposto) → round emergencial.
- Finding `high` (TLS fraco, header ausente, CVE por versão) → round normal.
- Só a URL não acha bug de código (SAST/IDOR/lógica) — combine com `pentest`.

## Anti-padrões

- ❌ Rodar isto contra site que não é seu sem autorização.
- ❌ Confundir com pentest completo — este é a **casca**; o miolo mora no código.
- ❌ Aumentar rate ou incluir payloads "só um pouquinho" — quebra a promessa passiva.
