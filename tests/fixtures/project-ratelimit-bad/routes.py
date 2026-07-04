# FIXTURE VULNERAVEL — comentarios neutros.
from fastapi import Request
from slowapi import Limiter

limiter = Limiter(key_func=lambda r: r.client.host)


@limiter.limit("5/minute")
async def change_password(request: Request):
    return {"ok": True}
