# FIXTURE BOA — @limiter.limit com response: Response.
from fastapi import Request, Response
from slowapi import Limiter

limiter = Limiter(key_func=lambda r: r.client.host)


@limiter.limit("5/minute")
async def change_password(request: Request, response: Response):
    return {"ok": True}
