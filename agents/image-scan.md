---
name: image-scan
category: supply-chain
module: 5
priority: P1
lead: security-lead
authority: implement
description: |
  CVE da IMAGEM, não das dependências. Camada estática (base fixada por digest?) sempre roda; camada dinâmica (Trivy/Grype na imagem) roda quando a imagem existe localmente — e quando não roda, sai skipped com missing_tool, nunca passed mudo.
---

# Agent: image-scan

`npm audit`, `check-deps-audit` e `check-osv-scanner` olham o que você declarou no
manifesto. **Nada ali enxerga o que veio junto na imagem base**: openssl, glibc,
zlib, curl, o runtime da própria linguagem, os utilitários que o mantenedor
achou útil incluir.

Um `node:20-slim` de seis meses atrás carrega dezenas de CVEs de sistema que
nenhum lockfile menciona. E o `check-trivy` existente roda `trivy fs` — varre o
sistema de arquivos do repositório, não as camadas da imagem construída.

## Duas camadas, e a segunda diz quando não rodou

**ESTÁTICA — sempre roda.** A base está fixada por digest, ou é tag móvel?

| Base | Severidade |
|---|---|
| `@sha256:…` | aprovado |
| `:latest` ou sem tag | **high** |
| `:20-slim` (tag sem digest) | **med** |

Tag móvel não é só falta de reprodutibilidade: é impossibilidade de auditar.
"Foi escaneado" perde o sentido quando `node:20` de hoje não é o de ontem.

**DINÂMICA — Trivy ou Grype na imagem de fato.** CVE `CRITICAL` vira **crit**,
`HIGH` vira **high**, com pacote e versão na mensagem.

## Por que o check não puxa a imagem sozinho

Um check não deve baixar gigabytes nem depender de rede para dar veredito. Ele
escaneia quando a imagem **já existe localmente** (`docker image inspect`
responde). Fora disso:

```bash
docker build -t meuapp:$(git rev-parse --short HEAD) .   # ou
BLINDAR_IMAGE=meuapp:abc123 bash templates/checks/check-image-scan.sh
BLINDAR_IMAGE_PULL=1 bash templates/checks/check-image-scan.sh   # autoriza o pull
```

Referência da imagem: `BLINDAR_IMAGE`, `.blindar/image.ref`, ou o `FROM` do
Dockerfile como último recurso.

## O fallback é declarado, nunca silencioso

Quando o scanner não existe, não responde, ou a imagem não está disponível, o
resultado sai **`skipped` com `missing_tool` preenchido** — não `passed`. Se
houver achado estático, sai `failed` com ele.

Isso vale especialmente para o caso mais perigoso: **binário instalado que
responde `--version` e falha no scan real**. Ele some da lista de pendências e o
verde vira mentira. Aqui, saída vazia do scanner é registrada como
`trivy:sem-saida`, não como imagem limpa.

## O que só se prova no registry

| Verificar | Por quê |
|---|---|
| A imagem **em produção** é a escaneada | escanear o build local não diz nada sobre o que subiu |
| CVE nova em imagem antiga | o scan de ontem não conhece a CVE publicada hoje — rescaneie periodicamente |
| A base é reconstruída, não só o app | `FROM` fixo por digest nunca recebe patch de sistema se ninguém subir o digest |
| Imagem final não carrega o toolchain | build multi-stage que copia demais leva compilador para produção |
