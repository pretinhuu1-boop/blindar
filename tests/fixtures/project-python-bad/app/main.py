# FIXTURE VULNERAVEL — Python. Os mesmos conceitos que o blindar cobra em JS.
import os, pickle, subprocess, hashlib, random, yaml
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

app = FastAPI()

# CORS liberado com credencial: qualquer origem le resposta autenticada
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True)

SEGREDO = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

@app.post("/login")
def login(email: str, senha: str):
    # hash fraco para senha
    h = hashlib.md5(senha.encode()).hexdigest()
    # token previsivel
    token = str(random.random())
    return {"token": token, "hash": h}

@app.get("/users/{uid}")
def get_user(uid: str, db=None):
    # SQL por concatenacao
    return db.execute(text("SELECT * FROM users WHERE id = " + uid)).fetchall()

@app.post("/exec")
def executar(cmd: str):
    # shell com input do usuario
    return subprocess.run(cmd, shell=True, capture_output=True)

@app.post("/carregar")
def carregar(blob: bytes, doc: str):
    # desserializacao insegura + yaml inseguro
    obj = pickle.loads(blob)
    cfg = yaml.load(doc)
    return {"obj": str(obj), "cfg": cfg}

@app.get("/todos")
def listar(db=None):
    # sem paginacao: devolve a tabela inteira
    return db.query(Todo).all()

@app.delete("/users/{uid}")
def apagar(uid: str, db=None):
    # hard delete, sem trilha
    db.query(User).filter(User.id == uid).delete()
    db.commit()
