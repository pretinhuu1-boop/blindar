# fixture: gitleaks-bad

Existe porque o `check-secrets` reportava `passed` com chave real em `src/`.

A causa: `gitleaks protect --staged` varria o índice, que numa auditoria está
vazio, achava nada, saía 0 — e o ramo que varria a árvore de trabalho nunca
rodava. O único fixture existente (`project-with-secrets`) tem os padrões
mascarados de propósito, então o gitleaks não disparava nele e o falso negativo
passou despercebido: o par de fixtures não cobria o caminho que quebrou.

Os segredos aqui são detectáveis DE VERDADE pelo gitleaks (é o ponto), mas não
são credencial de provedor: um JWT de exemplo público do jwt.io e uma chave
genérica. Nenhum dos dois é bloqueado pelo Push Protection do GitHub, então o
fixture pode viver num repositório público sem virar um segredo de mentira.
