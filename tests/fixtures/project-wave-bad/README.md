# fixture: wave-bad

Sem `.blindar/run-report.json`. O wave-guardian decide fechar ou não a onda
lendo esse arquivo — sem ele não há o que ler, e o certo é BLOQUEAR, não seguir.
Se este fixture não disparar, o guardião está liberando onda sobre dado que não
existe.
