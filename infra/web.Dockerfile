# Веб: сборка Vite и раздача nginx с прокси /api на контейнер api
FROM node:22-alpine AS build
WORKDIR /web
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
ARG VITE_AUTH_MODE=keycloak
ARG VITE_KEYCLOAK_URL=http://localhost:8080
ARG VITE_KEYCLOAK_REALM=darumen
ARG VITE_KEYCLOAK_CLIENT=darumen-web
ARG VITE_MAP_STYLE=https://tiles.openfreemap.org/styles/liberty
ENV VITE_AUTH_MODE=$VITE_AUTH_MODE VITE_KEYCLOAK_URL=$VITE_KEYCLOAK_URL VITE_KEYCLOAK_REALM=$VITE_KEYCLOAK_REALM \
    VITE_KEYCLOAK_CLIENT=$VITE_KEYCLOAK_CLIENT VITE_MAP_STYLE=$VITE_MAP_STYLE VITE_API_BASE=
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /web/dist /usr/share/nginx/html
COPY --from=build /web/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
