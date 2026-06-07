## Mudança

<!-- O que muda neste PR, em 1-3 frases -->

## Motivação

<!-- Qual bug real / dor observada motiva isso?
     Princípio do skill: "pago em PR vermelho mergeado".
     Se for nova regra/agent, precisa cenário real onde o atual falhou. -->

## Checklist

- [ ] `VERSION` foi bumpada (semver)
- [ ] `CHANGELOG.md` tem entrada da nova versão
- [ ] Se tocou em schema: validei contra exemplos reais
- [ ] Se tocou em agent: princípios não-negociáveis revistos
- [ ] Se tocou em pipeline: documentação atualizada
- [ ] Se quebrou contrato (.blindar/, schemas/): nota de migração no CHANGELOG
- [ ] CI verde (lint workflow)

## Testes

<!-- Como você sabe que isso funciona? -->

## Mudanças que NÃO devem entrar neste PR

- [ ] Refactor de outras partes não-relacionadas
- [ ] Mudança de defaults sem motivo explícito
- [ ] Tradução de PT-BR pra EN ou vice-versa (PR próprio)
