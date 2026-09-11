# Веб-клиент Darumen: сборка Vite → статический nginx, который проксирует /api к сервису api.
# VITE_* задаются на этапе сборки: режим авторизации headers, API того же origin.
FROM node:22-alpine AS build
WORKDIR /app
COPY apps/web/package.json apps/web/package-lock.json ./
RUN npm ci
COPY apps/web/ ./
ARG VITE_AUTH_MODE=headers
ARG VITE_API_BASE=
ENV VITE_AUTH_MODE=$VITE_AUTH_MODE VITE_API_BASE=$VITE_API_BASE
RUN npm run build

FROM nginx:1.27-alpine
COPY infra/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
