# Template: hierarquia de papéis (4 níveis)

> Padrão extraído do projeto Salon Pro 3.0 (NestJS + RolesGuard). Funciona
> em qualquer SaaS multi-tenant. Adaptável a outros domínios (e-com, saúde,
> educação) substituindo só os nomes — a estrutura permanece.

## Os 4 níveis

| Nível | Escopo | Permissões típicas |
|---|---|---|
| **MASTER** | Global (multi-tenant) | CRUD de tenants, billing, configuração global, audit de tudo |
| **ADMIN** | Por tenant | Controle total do tenant, gestão de usuários do tenant, configs |
| **GERENCIAL** (RECEPTION/MANAGER/COORDINATOR) | Operacional do tenant | Operação dia-a-dia: agenda, clientes, pedidos, estoque |
| **OPERACIONAL** (PROFESSIONAL/SELLER/DOCTOR/TEACHER) | Próprios dados | Vê e edita só o que é seu (própria agenda, próprias comissões) |

### Mapeamento por domínio

| Domínio | MASTER | ADMIN | GERENCIAL | OPERACIONAL |
|---|---|---|---|---|
| Beleza/Salão | Plataforma | Salão | Recepção | Profissional |
| E-commerce | Plataforma SaaS | Loja | Estoque/Pedidos | Vendedor |
| Saúde | Rede clínicas | Clínica | Recepção/Enfermaria | Médico |
| Educação | Rede | Escola | Coordenação | Professor |
| Serviços | Holding | Filial | Supervisão | Atendente |

## Schema do banco (Prisma)

```prisma
enum Role {
  MASTER
  ADMIN
  GERENCIAL
  OPERACIONAL
}

model User {
  id          String   @id @default(uuid())
  email       String   @unique
  passwordHash String
  pinHash     String?  // opcional, ver auth-premium.md
  role        Role
  tenantId    String?  // null se MASTER
  tenant      Tenant?  @relation(fields: [tenantId], references: [id])
  active      Boolean  @default(true)
  createdAt   DateTime @default(now())
  deletedAt   DateTime?

  // permissões granulares (opcional, ver seção abaixo)
  permissions Json?

  @@index([tenantId, role])
  @@index([email])
}

model Tenant {
  id       String  @id @default(uuid())
  name     String
  slug     String  @unique  // pra subdomain ou URL
  active   Boolean @default(true)
  users    User[]
  createdAt DateTime @default(now())
}
```

**Regras de banco:**
- Toda tabela tenant-scoped tem `tenantId` como **primeiro índice composto**
- RLS (Row-Level Security) no Postgres como defesa em profundidade
- MASTER bypassa filtro de `tenantId` (mas registra audit)

## Backend (NestJS — padrão do Salon Pro)

```ts
// auth/decorators/roles.decorator.ts
import { SetMetadata } from '@nestjs/common';
export const ROLES_KEY = 'roles';
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);

// auth/guards/roles.guard.ts
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<Role[]>(ROLES_KEY, [
      context.getHandler(), context.getClass(),
    ]);
    if (!required) return true;

    const { user } = context.switchToHttp().getRequest();
    if (!user?.role) throw new ForbiddenException('Acesso negado');

    // Hierarquia: MASTER vê tudo, ADMIN >= GERENCIAL >= OPERACIONAL
    const HIERARCHY = { MASTER: 4, ADMIN: 3, GERENCIAL: 2, OPERACIONAL: 1 };
    const userLevel = HIERARCHY[user.role] ?? 0;
    const minRequired = Math.min(...required.map(r => HIERARCHY[r]));
    if (userLevel < minRequired) throw new ForbiddenException('Permissão insuficiente');

    return true;
  }
}

// Uso em controller
@Controller('appointments')
@UseGuards(JwtAuthGuard, RolesGuard)
export class AppointmentsController {
  @Get()                                        // todos veem (filtrado por escopo)
  list(@Req() req) { return this.svc.list(req.user); }

  @Post()
  @Roles('GERENCIAL', 'ADMIN', 'MASTER')        // OPERACIONAL não cria
  create(@Body() dto: CreateDto, @Req() req) {
    return this.svc.create(dto, req.user);
  }

  @Delete(':id')
  @Roles('ADMIN', 'MASTER')                     // só admin+ deleta
  remove(@Param('id') id: string) { return this.svc.remove(id); }
}
```

## Filtragem por escopo (service layer)

OPERACIONAL nunca vê dados de outros — **regra no service, não no controller**:

```ts
async list(user: AuthUser) {
  const where: any = { tenantId: user.tenantId };

  if (user.role === 'OPERACIONAL') {
    where.assignedToId = user.id;     // só os seus
  }
  // GERENCIAL+ vê tudo do tenant
  // MASTER vê tudo (sem tenantId no where) — mas só se explicitamente pediu

  if (user.role === 'MASTER' && !ctx.includeAllTenants) {
    // MASTER por default age como ADMIN do tenant atual
    // Só vai cross-tenant quando passar ?allTenants=true
  }

  return this.prisma.appointment.findMany({ where });
}
```

## Frontend — guards de rota

```ts
// hooks/useRole.ts
export function useRole() {
  const user = useUser();
  const can = (action: string) => {
    const matrix = {
      'appointments.create': ['GERENCIAL', 'ADMIN', 'MASTER'],
      'appointments.delete': ['ADMIN', 'MASTER'],
      'users.manage':        ['ADMIN', 'MASTER'],
      'billing.view':        ['MASTER'],
      // ...
    };
    return matrix[action]?.includes(user?.role) ?? false;
  };
  return { user, can };
}

// Componente
const { can } = useRole();
{can('appointments.delete') && <Button onClick={remove}>Excluir</Button>}
```

**Regra:** frontend esconde, **backend bloqueia**. Nunca confiar só no front.

## Audit log obrigatório

Toda ação MASTER e toda ação destrutiva de qualquer role gera log:

```ts
await audit.log({
  actorId: user.id,
  actorRole: user.role,
  tenantId: user.tenantId,
  action: 'appointment.delete',
  targetId: appointmentId,
  ip: req.ip,
  userAgent: req.headers['user-agent'],
  timestamp: new Date()
});
```

## Permissões granulares (opcional — extensão)

Quando 4 roles não bastam, adicionar `permissions: Json` no User:

```json
{
  "appointments": ["read", "create"],
  "clients": ["read"],
  "inventory": []
}
```

Guard verifica role **OU** permission. Útil pra "gerente que tem acesso a
estoque mas não financeiro".

## Onboarding de tenant

```
MASTER cria tenant → cria ADMIN inicial → ADMIN convida GERENCIAL/OPERACIONAL
                                       → ADMIN configura tenant
```

- Provisioning automatizado (schema seeded, configs padrão, role MASTER cria)
- Email convite com token de 1 uso (expira em 48h)
- Primeiro login do ADMIN força troca de senha + cadastro PIN

## Testes obrigatórios

- [ ] OPERACIONAL não consegue acessar dados de outro OPERACIONAL (mesmo tenant)
- [ ] GERENCIAL não consegue acessar dados de outro tenant
- [ ] ADMIN não consegue criar outro ADMIN sem ser MASTER (configurável)
- [ ] MASTER consegue ver tudo mas gera audit em cada ação cross-tenant
- [ ] Token de usuário deletado/inativo retorna 401
- [ ] Mudança de role invalida tokens existentes (force re-login)
- [ ] Endpoint que pula `@Roles()` decorator é detectado em CI (test guard)

## Anti-padrões

- ❌ Role no JWT payload sem verificar no DB a cada request (token comprometido = role escalado pra sempre)
- ❌ Filtrar por role só no controller (esquece de filtrar `tenantId` no service)
- ❌ MASTER bypassar tenant sem audit (auditor regulatório quer rastrear)
- ❌ Frontend mostrar dados que backend deveria ter filtrado
- ❌ Permission matrix duplicada (frontend ≠ backend) — usar fonte única (ex: shared package)
- ❌ Mudança de role aceita sem MFA do MASTER
