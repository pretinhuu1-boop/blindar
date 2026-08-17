# Teste de isolamento entre tenants.
#
# Existe porque isolamento sem teste e promessa: o dia em que alguem esquecer o
# filtro de tenant numa query, nada avisa ate um cliente ver o dado do outro.
import pytest


def test_tenant_nao_ve_dado_de_outro(client, tenant_a, tenant_b):
    """Listagem do tenant A nao pode conter registro do tenant B."""
    client.post("/todos", json={"titulo": "do B"}, headers=tenant_b.headers)
    resposta = client.get("/todos", headers=tenant_a.headers)
    assert resposta.status_code == 200
    assert all(t["tenant_id"] == tenant_a.id for t in resposta.json())


def test_acesso_direto_por_id_de_outro_tenant_da_404(client, tenant_a, tenant_b):
    """Saber o id de um recurso alheio nao pode bastar para le-lo (IDOR)."""
    criado = client.post("/todos", json={"titulo": "do B"}, headers=tenant_b.headers).json()
    resposta = client.get(f"/todos/{criado['id']}", headers=tenant_a.headers)
    assert resposta.status_code == 404
