# Runbook — Segmentação de rede

> ⚠ **Parcialmente fora de escopo.** A parte em código/IaC está em
> [`agents/network-security.md`](../agents/network-security.md). A parte
> física/organizacional está aqui.

## O que o blindar JÁ cobre (em código)

- Security groups deny-by-default em IaC (Terraform/Pulumi/CDK)
- VPC com subnets pública/privada/data
- DB nunca em subnet pública
- Headers de segurança + WAF rules
- Rate limiting em camada de app

## O que fica FORA do código (responsabilidade infra/SecOps)

- VLAN física entre datacenters / racks
- Switch ACLs em hardware
- IDS/IPS hardware (Snort, Suricata físico)
- DMZ tradicional
- Air-gap de redes OT/SCADA (industrial)

## Política mínima sugerida

| Camada | Princípio |
|---|---|
| Network | Subnets isoladas por tier (web / app / data) |
| Comunicação | TLS interno também (zero trust) |
| Admin access | VPN + MFA + bastion host |
| Database | Sem IP público. Acessível só via security group de app |
| Build runners | Sem credenciais de prod. Token efêmero por job |

## Mapeamento de frameworks

- **ISO 27001 A.8.20-A.8.22** — networks security
- **NIST CSF PR.AC-5** — protective tech
- **CIS Control 12** — network infrastructure mgmt
- **PCI-DSS Req 1** — install/maintain network security controls
