FROM node:20-slim
WORKDIR /app
COPY . .
RUN npm ci --omit=dev
CMD ["node", "src/server.js"]
