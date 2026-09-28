# Веб-клиент Darumen: сборка Vite → статический nginx, который проксирует /api к сервису api и /auth к Keycloak.
# VITE_* задаются на этапе сборки: Keycloak стенда за тем же origin (/auth), API того же origin.
FROM node:22-alpine AS build
WORKDIR /app
COPY apps/web/package.json apps/web/package-lock.json ./
RUN npm ci
COPY apps/web/ ./
ARG VITE_KEYCLOAK_URL=https://dc.jurek.kz/auth
ARG VITE_KEYCLOAK_REALM=darumen
ARG VITE_KEYCLOAK_CLIENT=darumen-web
ARG VITE_API_BASE=
# доступность входа через eGov приходит из API (GET /api/v1/public/service-status), флага сборки для неё нет
ENV VITE_KEYCLOAK_URL=$VITE_KEYCLOAK_URL VITE_KEYCLOAK_REALM=$VITE_KEYCLOAK_REALM VITE_KEYCLOAK_CLIENT=$VITE_KEYCLOAK_CLIENT \
    VITE_API_BASE=$VITE_API_BASE
RUN npm run build

FROM nginx:1.27-alpine
COPY infra/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
