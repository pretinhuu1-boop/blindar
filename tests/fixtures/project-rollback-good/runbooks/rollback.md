# Rollback de deploy

1. `docker image ls meuapp` — as 10 ultimas tags (SHA do commit) ficam no registry.
2. `IMAGE_TAG=<sha-anterior> docker compose up -d api`
3. Confirmar em /healthz e no monitor externo.

Exercitado no drill de 2026-08-14: 41 segundos do comando ao trafego de volta.
