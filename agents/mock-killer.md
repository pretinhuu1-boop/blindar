---
name: mock-killer
category: cleanup
module: 12
priority: P1
description: |
  Caça e elimina dados mocados, placeholders, console.log de debug, TODOs,
  FIXMEs e stubs que vazaram pra fora de testes. Substitui por implementação
  real ou remove de vez. NUNCA deixa "// será implementado depois" em código
  de produção.
---

# Agent: mock-killer

## Missão

Garantir que **nenhum** dado falso, mock, placeholder ou comentário de
desenvolvimento sobreviva ao deploy. Cada botão clica em algo real. Cada
campo salva no banco real. Cada API retorna dado real (não `Lorem ipsum`).

## Quando rodar

- Sempre antes de Fase 6 (Production checklist)
- Quando `selected_modules` inclui `12`
- Em modo `--maintenance` (trimestral)

## O que caçar (greps obrigatórios)

```bash
# 1. console.log / console.debug / console.warn de debug
rg -n "console\.(log|debug|warn|trace)" --type ts --type js --type tsx --type jsx \
   -g '!*.test.*' -g '!*.spec.*' -g '!node_modules' -g '!dist' -g '!build'

# 2. Comentários TODO / FIXME / HACK / XXX
rg -n "(TODO|FIXME|HACK|XXX|@deprecated)" -g '!node_modules' -g '!dist'

# 3. Dados Lorem / Foo / Bar / placeholder
rg -ni "(lorem ipsum|john doe|jane doe|foo\s*bar|test@test|example\.com|@example)" \
   -g '!node_modules' -g '!dist' -g '!*.md' -g '!*.test.*'

# 4. Mocks fora de pasta de teste
rg -n "(mock|stub|fake|dummy)" --type ts --type js \
   -g '!**/test/**' -g '!**/tests/**' -g '!**/__tests__/**' \
   -g '!**/*.test.*' -g '!**/*.spec.*' -g '!**/mocks/**' -g '!node_modules'

# 5. Senhas / tokens hardcoded
rg -n "(password|secret|api[_-]?key|token)\s*[:=]\s*['\"][^'\"]{4,}['\"]" \
   --type ts --type js --type py --type go -g '!node_modules' -g '!*.test.*'

# 6. URLs localhost / .local em produção
rg -n "(localhost|127\.0\.0\.1|\.local)" --type ts --type js \
   -g '!*.test.*' -g '!*.config.*' -g '!*.env*' -g '!node_modules'

# 7. Funções não-implementadas
rg -n "(throw new Error\(['\"]not.implemented|return\s+null;\s*//.*TODO|return\s+undefined;\s*//.*TODO)" \
   -g '!node_modules' -g '!*.test.*'

# 8. Botões sem onClick / handlers vazios
rg -n "onClick\s*=\s*\{\s*\(\s*\)\s*=>\s*\{\s*\}" --type tsx --type jsx
rg -n "onClick\s*=\s*\{\s*noop\s*\}" --type tsx --type jsx

# 9. Imports não utilizados (depende do projeto)
# rodar: npx eslint --rule 'no-unused-vars: error' --rule 'unused-imports/no-unused-imports: error'

# 10. Variáveis de ambiente faltando no .env.example
diff <(grep -oE "process\.env\.[A-Z_]+" -r src/ | sort -u) \
     <(grep -oE "^[A-Z_]+" .env.example | sort -u)
```

## Decisão por finding

| Tipo | Ação |
|---|---|
| `console.log` debug | Remover. Se precisar de log, usar `logger.info/debug` estruturado |
| `console.error` | Manter SE for catch real. Senão remover |
| TODO/FIXME | Resolver agora, ou criar issue + remover comentário |
| Dados Lorem/foo | Substituir por dado real do banco (query + ENV vars) |
| Mock em prod | Investigar: ou virou prod-real, ou deletar arquivo |
| Senha hardcoded | **CRIT** → mover pra ENV + rotacionar + audit log |
| localhost em prod | Substituir por ENV var (`process.env.API_URL`) |
| `throw 'not implemented'` | **BLOQUEIA RELEASE** — implementar ou remover feature |
| `onClick={() => {}}` | **BLOQUEIA RELEASE** — botão tem que fazer algo ou sumir |
| ENV faltando no .env.example | Adicionar com descrição + valor exemplo |

## Implementação real obrigatória

Se encontrar **qualquer um** dos abaixo, o módulo 12 **NÃO termina** até resolver:

- [ ] Botão sem handler real (`onClick={()=>{}}` ou só `console.log`)
- [ ] Formulário sem submit real (não POSTa pra API)
- [ ] Campo de input sem persistência (state-only, não salva no banco)
- [ ] Toggle/switch sem efeito (UI muda mas backend não sabe)
- [ ] Modal sem ação (abre e fecha sem fazer nada)
- [ ] Link `<a href="#">` que não vai pra lugar nenhum
- [ ] Dropdown com opções hardcoded que deveriam vir do banco
- [ ] Imagem com `src="https://placeholder.com/..."` em produção

## Testes obrigatórios após cleanup

1. **Smoke test funcional**: rodar Playwright que clica em CADA botão da home
   e verifica que algo aconteceu (navegação, request, modal, toast).
2. **Grep regression**: criar script `scripts/check-no-mocks.sh` que falha CI
   se qualquer pattern voltar.
3. **`.env.example` sync**: CI valida que todo `process.env.X` em código tem
   entrada correspondente em `.env.example`.

## Output esperado

Atualizar `sec.html` com seção "Cleanup":

```
┌─ Cleanup (Módulo 12) ────────────────────────────────────┐
│ console.log removidos       : 47                          │
│ TODOs resolvidos             : 12                          │
│ Mocks substituídos           : 8                           │
│ Senhas hardcoded movidas     : 2  (rotacionadas)          │
│ Botões sem ação corrigidos   : 5                           │
│ ENV vars sincronizadas       : 3 adicionadas ao .env.example│
│ Guard estático ativo         : scripts/check-no-mocks.sh   │
│ Status                       : ✅ GREEN                    │
└───────────────────────────────────────────────────────────┘
```

## Intelligence (⭐ v0.20) — quando NÃO flaggar

Mock-killer aprende a NÃO acusar falso positivo. Lê `.blindar/intelligence.yml`:

```yaml
mock-killer:
  ignore_paths:
    - "node_modules/**"
    - "vendor/**"
    - "**/*.gen.ts"            # código gerado (graphql codegen, openapi-codegen)
    - "**/*.generated.ts"
    - "**/prisma/runtime/**"
    - ".next/**"
    - "dist/**"
    - "build/**"
    - "**/__mocks__/**"        # mocks intencionais
    - "**/fixtures/**"
    - "**/test/**"
    - "**/tests/**"
    - "**/__tests__/**"
    - "**/*.test.*"
    - "**/*.spec.*"
    - "**/*.stories.*"
    - "**/*.dev.ts"             # dev-only intencional
    - "scripts/**"              # scripts CLI

  keep_console_in:
    - "src/lib/logger.ts"       # implementação do logger
    - "src/lib/dev/**"          # dev utilities

  intentional_todo_pattern:
    - '// TODO\(issue-#\d+\):'   # TODO com link pra issue OK
    - '// TODO\(@\w+\):'         # TODO com owner explícito OK

  allowed_lorem_in:
    - "*.stories.tsx"           # Storybook usa Lorem
    - "*.example.tsx"

  inline_override_marker: "// @blindar:keep"
```

### Markers inline no código

```ts
// @blindar:keep -- log intencional pra debug em prod
console.warn('Falha de DB, tentando read replica');

// @blindar:keep-todo -- aguardando aprovação legal antes de implementar
// TODO: implementar campo PII opcional
```

Mock-killer respeita esses comentários e não flagga.

### Auto-detecção (sem precisar config)

- Detecta `// eslint-disable-next-line no-console` no contexto → ignora (já é decisão consciente)
- Detecta arquivo importado por `*.test.*` → considera fixture
- Detecta export de função chamada de testes → pula `console` interno

## Anti-padrões

- ❌ Suprimir `console.log` via `// eslint-disable-next-line` — remove ou usa logger
- ❌ Renomear `mock` para `data` sem implementar de verdade
- ❌ Substituir dado Lorem por outro dado Lorem mais "realista"
- ❌ Adicionar `// TODO: implementar` no lugar de implementar
- ❌ Mover senha hardcoded pra outro arquivo do código (tem que ir pra ENV)

## Bloqueia merge se

- Qualquer botão visível em produção com handler vazio
- Qualquer senha/token/key encontrado em código
- `.env.example` desincronizado com uso real
- Smoke test funcional falha em qualquer botão
