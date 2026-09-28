# Прод-образ Keycloak для стенда: БД Postgres, health на management-порту 9000, путь /auth, темы darumen внутри.
# Build-time опции (db, health, http-relative-path) зашиты `kc.sh build`, поэтому контейнер стартует
# `start --optimized` без пересборки Quarkus при каждом запуске (~10 с вместо ~40 с).
# Контекст сборки — infra/keycloak (корневой .dockerignore исключает этот каталог из контекста корня).
# Версия — та же, что на стенде до перехода на Postgres (26.0.8); keycloak-config-cli собран под 26.0.x.
ARG KEYCLOAK_VERSION=26.0.8

FROM quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} AS builder
ENV KC_DB=postgres \
    KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=false \
    KC_HTTP_RELATIVE_PATH=/auth
# Темы входа и писем (loginTheme/emailTheme=darumen): в prod-режиме Keycloak кэширует темы, правка — через новый образ
COPY --chown=keycloak:keycloak themes/darumen /opt/keycloak/themes/darumen
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:${KEYCLOAK_VERSION}
COPY --from=builder /opt/keycloak/ /opt/keycloak/
# Один узел: локальный кэш Infinispan вместо кластера (в 26.0 это runtime-опция, поэтому ENV финального образа)
ENV KC_CACHE=local
# Realm для первого старта на пустой БД (`--import-realm` пропускает существующий realm, пользователей не трогает).
# Дальнейшие правки realm применяет сервис realm-sync (keycloak-config-cli) — см. config-cli.Dockerfile.
COPY --chown=keycloak:keycloak darumen-realm.json /opt/keycloak/data/import/darumen-realm.json
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized", "--import-realm"]
