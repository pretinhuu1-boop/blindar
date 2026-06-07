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
```

## Riscos aceitos atualmente

<!-- O skill insere aqui. Apagar este comentário ao popular. -->

_Nenhum risco aceito ainda._
