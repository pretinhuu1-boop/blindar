---
name: grpc-internal
category: api
module: 4
priority: P2
description: |
  gRPC para comunicação interna entre microservices: Protobuf como
  contrato versionado, streaming bidirecional, deadline obrigatório,
  retry com backoff, mTLS, tracing W3C, schema-first. NÃO usar gRPC pra
  cliente público (REST/GraphQL melhor) — só serviços internos.
---

# Agent: grpc-internal

## Missão

gRPC é 5-10x mais rápido que JSON+REST para tráfego interno. Mas é
overkill (e pior DX) pra cliente público. Este agente prescreve gRPC
no escopo certo.

## Quando rodar

- Módulo 4 selecionado
- Arquitetura microservices com >3 services se comunicando
- Detectado: `.proto`, `@grpc/grpc-js`, `grpcio`, `tonic`
- NÃO rodar pra API pública

## A. Quando usar gRPC

| Vale | NÃO vale |
|---|---|
| Service→service interno | API pública pra cliente |
| Streaming bidirecional | CRUD simples |
| Latência ultra-baixa importante | Browser direto (precisa gRPC-Web proxy) |
| Polyglot (Go+Java+Python falando entre si) | Tudo Node.js |

## B. Protobuf como contrato

```protobuf
// appointments.proto
syntax = "proto3";
package salon.v1;

service AppointmentService {
  rpc Create(CreateAppointmentRequest) returns (Appointment);
  rpc List(ListAppointmentsRequest) returns (stream Appointment);   // streaming
  rpc Watch(WatchRequest) returns (stream Event);                    // bidirecional
}

message Appointment {
  string id = 1;
  string tenant_id = 2;
  google.protobuf.Timestamp scheduled_at = 3;
  Status status = 4;
  reserved 5, 6;                                    // campos removidos (não reuse number!)
  reserved "old_field_name";
}

enum Status {
  STATUS_UNSPECIFIED = 0;                           // SEMPRE primeiro
  STATUS_SCHEDULED = 1;
  STATUS_CONFIRMED = 2;
  STATUS_COMPLETED = 3;
}
```

**Versionamento**: namespace `v1`, `v2`. NUNCA reusar field numbers.

## C. Deadline obrigatório

```ts
const deadline = new Date(Date.now() + 5_000);    // 5s
client.list(request, { deadline }, (err, res) => { ... });
```

Server side:
```ts
@GrpcMethod('AppointmentService', 'Create')
async create(req, metadata, call) {
  if (call.deadline && call.deadline < Date.now()) {
    throw new RpcException({ code: status.DEADLINE_EXCEEDED });
  }
  // ...
}
```

Sem deadline, RPCs travadas acumulam.

## D. mTLS entre services

```ts
const credentials = grpc.credentials.createSsl(
  fs.readFileSync('ca.crt'),
  fs.readFileSync('client.key'),
  fs.readFileSync('client.crt'),
);
```

Service A só aceita conexões de services com cert válido (assinado pela CA interna).

## E. Retry + circuit breaker

```ts
const channelOptions = {
  'grpc.service_config': JSON.stringify({
    methodConfig: [{
      name: [{}],
      retryPolicy: {
        maxAttempts: 3,
        initialBackoff: '0.1s', maxBackoff: '1s', backoffMultiplier: 2,
        retryableStatusCodes: ['UNAVAILABLE', 'DEADLINE_EXCEEDED']
      }
    }]
  })
};
```

Circuit breaker via Istio service mesh ou lib (`opossum` adaptada).

## F. Tracing W3C

```ts
// Auto-propaga trace context
import { tracer } from '@opentelemetry/api';
import { GrpcInstrumentation } from '@opentelemetry/instrumentation-grpc';
registerInstrumentations({ instrumentations: [new GrpcInstrumentation()] });
```

Cada RPC vira span. Cross-service correlation automática.

## G. Health checking

```protobuf
service Health {
  rpc Check(HealthCheckRequest) returns (HealthCheckResponse);
  rpc Watch(HealthCheckRequest) returns (stream HealthCheckResponse);
}
```

LB usa pra remover instance unhealthy.

## H. NÃO browser direto

Browser não fala HTTP/2 gRPC nativo. Precisa:
- **gRPC-Web** proxy (Envoy)
- OU usar REST/GraphQL pra browser, gRPC só interno

## I. Codegen

```bash
# TS
protoc --plugin=protoc-gen-ts_proto=node_modules/.bin/protoc-gen-ts_proto \
       --ts_proto_out=. appointments.proto

# Go
protoc --go_out=. --go-grpc_out=. appointments.proto

# Python
python -m grpc_tools.protoc --python_out=. --grpc_python_out=. appointments.proto
```

Generated code em `gen/` (versionado).

## J. Greps

```bash
# RPC sem deadline
rg -n "client\.(call|invoke|\\w+)\(" --type ts -A 3 | rg -v "deadline"

# Reuso de field number (CRIT em proto)
git log --all -p -- '*.proto' | rg "^\+\\s+(\\w+) = " | sort | uniq -d

# Service sem health check
find . -name '*.proto' -exec grep -L "service Health" {} \;
```

## Output em sec.html

```
┌─ gRPC Internal (Módulo 4) ───────────────────────────────┐
│ Services com gRPC             : 7                         │
│ Protobuf versionado (v1/v2)   : ✅                        │
│ Deadlines obrigatórios        : ✅ 100% RPCs              │
│ mTLS entre services           : ✅                        │
│ Retry policy configurado      : ✅                        │
│ Tracing W3C                   : ✅ OpenTelemetry          │
│ Health checks                 : ✅                        │
│ Codegen em CI                 : ✅                        │
│ Breaking change check (Buf)   : ✅                        │
│ gRPC-Web pra browser          : ❌ não exposto            │
│ Status                        : ✅ INTERNAL-READY        │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ gRPC pra cliente público
- ❌ RPC sem deadline (acumula travado)
- ❌ Reuso de field number em proto (corrompe wire format)
- ❌ Breaking change sem `reserved`
- ❌ Service sem health check
- ❌ Codegen manual fora do CI (drift)
- ❌ Plaintext entre services em prod
- ❌ Sem retry config (1 packet drop = erro)
- ❌ Field `enum X { A = 0; }` sem `X_UNSPECIFIED = 0` (causa bug em rolling update)
- ❌ Streaming sem backpressure handling
- ❌ Sem tracing (debug cross-service impossível)
