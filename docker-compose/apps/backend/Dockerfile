FROM node:20-alpine
RUN apk add --no-cache openssl
WORKDIR /app
COPY spiffe-workload-api/ spiffe-workload-api/
COPY backend/package.json .
RUN npm install --omit=dev
COPY backend/src/ src/
RUN adduser -D -u 10002 backend && chown -R backend:backend /app
USER backend
EXPOSE 8443 8444
CMD ["node", "src/index.js"]
