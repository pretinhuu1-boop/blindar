# FIXTURE VULNERAVEL — lista fixa de deps dessincroniza do manifesto.
FROM python:3.12-slim
WORKDIR /app
RUN pip install fastapi uvicorn slowapi
COPY . .
CMD ["uvicorn", "main:app"]
