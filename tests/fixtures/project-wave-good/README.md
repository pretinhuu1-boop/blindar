# fixture: wave-good

Run-report presente, tudo passou, zero errored. Disparo aqui é falso positivo.

## O insumo deste fixture e o `.blindar/run-report.json`

`check-wave-guardian` LE esse arquivo para decidir se a onda fecha. Sem ele o
check reprova por falta de pre-requisito — e o fixture "limpo" passa a acusar
falso-positivo que nao existe.

Os arquivos que o check ESCREVE aqui (`.blindar/results/`,
`.blindar/wave-N-guardian.md`) sao produto da rodada e ficam fora do
versionamento, pela regra do `.gitignore`.
