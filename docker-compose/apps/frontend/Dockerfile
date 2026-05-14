FROM node:20-alpine
RUN apk add --no-cache openssl
WORKDIR /app
COPY spiffe-workload-api/ spiffe-workload-api/
COPY frontend/package.json .
RUN npm install --omit=dev
COPY frontend/src/ src/
RUN adduser -D -u 10001 frontend && chown -R frontend:frontend /app
USER frontend
EXPOSE 3000
CMD ["node", "src/index.js"]
