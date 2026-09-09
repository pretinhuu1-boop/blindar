# Riscos aceitos — {project_name}

Documento gerado pelo `blindar`. Lista todo risco que foi **conscientemente
não-mitigado** durante o hardening. Cada entrada é uma decisão explícita.

## Formato

```markdown
## RISK-NNN — {título curto}

- **Severidade**: crit | high | med | low
- **Categoria**: web_api | auth | supply_chain | compliance | ...
- **ATK relacionado**: ATK-XXX (se houver no catálogo do sec.html)
- **Por que aceito**:
  Texto livre. Por que não foi mitigado.
- **Mitigação compensatória**:
  O que está em vigor mesmo sem fix direto.
- **Condições pra reabrir**:
  Quando esse risco vira fix obrigatório (ex: "se passar 10k usuários",
  "se LGPD ANPD emitir orientação", etc.).
- **Aceito por**: nome + data
- **Próxima revisão**: data (default: 90 dias)
- **fp**: `fp:xxxxxxxx` — a impressão digital do achado, copiada do
  `findings[].fp` do `.blindar/results/check-*.json`
```

## A linha `fp:` é o que liga o aceite ao achado

Sem ela o texto acima é documentação para humano e mais nada: o gate re-lista o
achado como **novo** a cada rodada, e separar "entrou neste ciclo" de "baseline
já triado" volta a ser trabalho manual — sendo que essa é a única pergunta que
decide o GO.

Com a linha, o `check-release-gates.sh` casa por impressão digital (agente +
arquivo + mensagem normalizada, com dígitos colapsados), e passa a dizer
`0 crit/high NOVO` com o baseline aceito ao lado. Casar por CAMINHO seria pior:
um segundo achado no mesmo arquivo herdaria o aceite do primeiro.

Onde achar a impressão digital:

```bash
jq -r '.findings[] | "\(.fp)  \(.severity)  \(.file)  \(.message[0:70])"'   .blindar/results/check-security.json
```

Duas coisas que o aceite **não** faz, de propósito:

- **Não vira verde limpo.** Crit aceito derruba o veredito para
  `CONDITIONAL GO` e sai nomeado no relatório. "Alguém assinou" é diferente de
  "não existe" — no dia em que as duas coisas ficarem indistinguíveis, este
  arquivo vira o lugar onde se esconde crit.
- **Não sobrevive à mudança do achado.** Editar o código muda a mensagem, a
  impressão digital muda junto, e o achado volta como novo. É o comportamento
  desejado: o aceite valia para aquele achado, não para aquele arquivo.

## Riscos aceitos atualmente

<!-- O skill insere aqui. Apagar este comentário ao popular. -->

_Nenhum risco aceito ainda._
