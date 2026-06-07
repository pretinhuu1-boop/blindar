# Spec: Load-test harness no termination (item #6 do ROADMAP)

> Adicionar load-test mensurável como gate da Fase 5 antes de declarar
> projeto "production-ready".

## Problema

Hoje termination olha coverage (ATKs fechados). **Não testa se sistema
aguenta carga real**. Você pode ter 90% ATKs covered mas cair em 100
usuários simultâneos.

## Solução

Gate novo na Fase 5 (production checklist):

| Gate | Como | Bloqueia |
|---|---|---|
| **Load test** | k6/vegeta/Locust com 3x carga declarada | sim |

Operador declara em `.blindar/config.yml`:

```yaml
load_test:
  expected_rps: 100
  test_factor: 3
  slo_p95_ms: 500
  slo_error_rate_pct: 1
  duration_min: 5
  endpoints:
    - path: /api/users
      weight: 50
    - path: /api/orders
      weight: 30
    - path: /api/search
      weight: 20
```

Skill gera `loadtest/k6-blindar.js` (template):

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: __ENV.RPS },
    { duration: '3m', target: __ENV.RPS },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<' + __ENV.P95_MS],
    http_req_failed: ['rate<' + (__ENV.ERROR_RATE / 100)],
  },
};

export default function () {
  // gerado a partir de endpoints+weights do config
  const r = Math.random() * 100;
  if (r < 50) http.get(`${__ENV.HOST}/api/users`);
  else if (r < 80) http.get(`${__ENV.HOST}/api/orders`);
  else http.get(`${__ENV.HOST}/api/search`);
  sleep(1);
}
```

## Execução

Roda contra **staging**, nunca prod:

```bash
RPS=300 P95_MS=500 ERROR_RATE=1 HOST=https://staging \
  k6 run loadtest/k6-blindar.js
```

Skill orquestra:
1. Detecta se k6 está instalado, senão sugere instalação
2. Roda contra HOST=$BLINDAR_STAGING_URL (env var)
3. Captura output JSON do k6
4. Compara p95 e error_rate com SLO
5. Se passa: gate ✓
6. Se falha: round novo na Fase 3 (categoria `scalability`)

## Critério

Passa se:
- p95 < SLO declarado
- error_rate < SLO declarado
- nenhum 5xx em endpoints críticos

Falha se qualquer um acima OU staging caiu durante o teste (servidor
crashou = bug critico).

## Por que não implementei agora

1. **Requer staging real** — não dá pra testar contra `localhost` que
   roda na máquina do dev. Time precisa ter staging acessível.
2. **Decisão de ferramenta**: k6 (open-source, JS), Locust (Python),
   vegeta (Go), Artillery (Node). Cada uma com tradeoff. Não quis
   travar em uma sem feedback.
3. **Sem load test atual no projeto-alvo** = nada pra comparar. Skill
   teria que gerar baseline + comparar com proximo run.

## Quando faz sentido implementar

- Projeto com SLO declarado
- Staging acessível
- Time já usa alguma ferramenta de load (preferência: k6 ou Locust)
- Pré-launch real (não toy project)

## Mapeamento de frameworks

- AWS Well-Architected: Reliability Pillar
- NIST CSF: PR.IP-9 (response plans)
- SOC 2: A1.1 (availability commitment)
