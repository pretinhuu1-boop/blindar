# FIXTURE LIMPO — mesma aplicacao do project-python-bad, sem os problemas.
import os, secrets, subprocess, yaml
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter
from slowapi.util import get_remote_address
from argon2 import PasswordHasher
from sqlalchemy import text, func
from .seguranca import HeadersSeguranca

app = FastAPI()
app.add_middleware(HeadersSeguranca)
limiter = Limiter(key_func=get_remote_address)

# CORS restrito a origens conhecidas, lidas do ambiente
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ["ORIGENS_PERMITIDAS"].split(","),
    allow_credentials=True,
)

ph = PasswordHasher()


def usuario_atual(token: str = ""):
    """Guarda de autenticacao usada por toda rota que mexe em dado."""
    if not token:
        raise HTTPException(status_code=401)
    return {"id": "1"}


# @blindar:public-ok — login precisa ser publico por definicao; a protecao
# aqui e o rate limit, nao a autenticacao.
@app.post("/login")
@limiter.limit("5/minute")
def login(email: str, senha: str):
    h = ph.hash(senha)
    token = secrets.token_urlsafe(32)
    return {"token": token, "hash": h}


@app.get("/users/{uid}")
def get_user(uid: str, db=None, atual=Depends(usuario_atual)):
    # query parametrizada: o valor nunca vira parte do SQL
    return db.execute(text("SELECT * FROM users WHERE id = :id"), {"id": uid}).fetchall()


@app.post("/exec")
def executar(operacao: str, atual=Depends(usuario_atual)):
    # mapa fechado: nada do usuario chega ao shell
    permitidas = {"status": ["systemctl", "is-active", "app"]}
    if operacao not in permitidas:
        raise HTTPException(status_code=400)
    return subprocess.run(permitidas[operacao], shell=False, capture_output=True)


@app.post("/carregar")
def carregar(doc: str, atual=Depends(usuario_atual)):
    # yaml seguro; nada de pickle vindo de fora
    return {"cfg": yaml.safe_load(doc)}


@app.get("/todos")
def listar(db=None, limite: int = 50, offset: int = 0, atual=Depends(usuario_atual)):
    # paginacao obrigatoria, com teto
    return db.query(Todo).limit(min(limite, 100)).offset(offset).all()


@app.delete("/users/{uid}")
def apagar(uid: str, db=None, atual=Depends(usuario_atual)):
    # soft delete + trilha de auditoria
    db.query(User).filter(User.id == uid).update({"deleted_at": func.now()})
    db.add(AuditLog(acao="user.delete", alvo=uid))
    db.commit()
