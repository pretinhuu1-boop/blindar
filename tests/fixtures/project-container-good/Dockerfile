FROM node:20.11.1-slim@sha256:0e07bfc3d4b0d5ea5b2a4d4f38a4d3f8b53c0e4b8ab9d4f2b0f6c1a2d3e4f5a6
WORKDIR /app
COPY . .
RUN npm ci --omit=dev
RUN addgroup --system app && adduser --system --ingroup app app
USER app
CMD ["node", "src/server.js"]
