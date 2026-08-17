# Middleware de headers de seguranca.
#
# Em Python nao existe um `helmet` de facto, entao o padrao e escrever o
# middleware — e por isso o check cobra os headers, nao a biblioteca.
from starlette.middleware.base import BaseHTTPMiddleware


class HeadersSeguranca(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        resposta = await call_next(request)
        resposta.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains; preload"
        resposta.headers["X-Content-Type-Options"] = "nosniff"
        resposta.headers["X-Frame-Options"] = "DENY"
        resposta.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        resposta.headers["Content-Security-Policy"] = "default-src 'self'; frame-ancestors 'none'"
        resposta.headers["Permissions-Policy"] = "geolocation=(), camera=(), microphone=()"
        return resposta
