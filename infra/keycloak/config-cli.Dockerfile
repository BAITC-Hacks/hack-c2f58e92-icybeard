# realm-sync: keycloak-config-cli с realm darumen внутри. Одноразовый контейнер после старта Keycloak приводит realm
# к файлу (настройки, клиенты, роли, демо-пользователи, SMTP, секрет darumen-admin), НЕ удаляя данных стенда:
# пользователи вне файла, их пароли и TOTP, группы и роли, созданные на стенде, не трогаются.
# Контекст сборки — infra/keycloak. Тег `6.5.1-26.0.5` — config-cli 6.5.1, собранный под Keycloak 26.0.x.
ARG CONFIG_CLI_IMAGE=adorsys/keycloak-config-cli:6.5.1-26.0.5

FROM ${CONFIG_CLI_IMAGE}
USER root
COPY render-realm.sh /tmp/render-realm.sh
COPY darumen-realm.json /tmp/darumen-realm.json
# ${VAR:default} (синтаксис Keycloak) → $(env:VAR:-default) (синтаксис config-cli); переменные берутся из окружения
# контейнера realm-sync — тот же набор, что у сервиса keycloak (x-realm-env в docker-compose.prod.yml)
RUN mkdir -p /config \
 && sh /tmp/render-realm.sh /tmp/darumen-realm.json > /config/darumen-realm.json \
 && rm /tmp/render-realm.sh /tmp/darumen-realm.json
USER 65534

# Политика импорта (README config-cli, раздел Import options; docs/MANAGED.md):
#  - IMPORT_CACHE_ENABLED=false — применять файл при каждом запуске, а не только при смене контрольной суммы
#    (иначе смена SMTP-пароля или секрета в .env без правки файла не применится);
#  - IMPORT_MANAGED_*=no-delete — config-cli только создаёт и обновляет, никогда не удаляет роли, группы, клиенты,
#    компоненты и т. п. (удалить сущность из realm — руками в консоли); пользователей config-cli не удаляет вообще;
#  - IMPORT_USERS_MERGEROLES/MERGEGROUPS=true — демо-пользователям роли и группы только добавляются, выданные на
#    стенде не снимаются;
#  - пароли демо-пользователей помечены userLabel "initial" — задаются только при создании пользователя, смена
#    пароля на стенде синхронизацией не откатывается;
#  - KEYCLOAK_AVAILABILITYCHECK_TIMEOUT=60s — realm-sync стартует после healthy Keycloak, долгое ожидание только
#    оттягивает ошибку (неверный пароль администратора config-cli тоже принимает за «недоступен»).
ENV IMPORT_FILES_LOCATIONS=file:/config/darumen-realm.json \
    IMPORT_VARSUBSTITUTION_ENABLED=true \
    IMPORT_CACHE_ENABLED=false \
    IMPORT_REMOTESTATE_ENABLED=true \
    IMPORT_USERS_MERGEROLES=true \
    IMPORT_USERS_MERGEGROUPS=true \
    IMPORT_MANAGED_AUTHENTICATIONFLOW=no-delete \
    IMPORT_MANAGED_GROUP=no-delete \
    IMPORT_MANAGED_REQUIREDACTION=no-delete \
    IMPORT_MANAGED_CLIENTSCOPE=no-delete \
    IMPORT_MANAGED_SCOPEMAPPING=no-delete \
    IMPORT_MANAGED_CLIENTSCOPEMAPPING=no-delete \
    IMPORT_MANAGED_COMPONENT=no-delete \
    IMPORT_MANAGED_SUBCOMPONENT=no-delete \
    IMPORT_MANAGED_IDENTITYPROVIDER=no-delete \
    IMPORT_MANAGED_IDENTITYPROVIDERMAPPER=no-delete \
    IMPORT_MANAGED_ROLE=no-delete \
    IMPORT_MANAGED_CLIENT=no-delete \
    IMPORT_MANAGED_CLIENTAUTHORIZATIONRESOURCES=no-delete \
    IMPORT_MANAGED_CLIENTAUTHORIZATIONPOLICIES=no-delete \
    IMPORT_MANAGED_CLIENTAUTHORIZATIONSCOPES=no-delete \
    IMPORT_MANAGED_MESSAGEBUNDLES=no-delete \
    IMPORT_MANAGED_WORKFLOW=no-delete \
    KEYCLOAK_AVAILABILITYCHECK_ENABLED=true \
    KEYCLOAK_AVAILABILITYCHECK_TIMEOUT=60s \
    JAVA_OPTS="-Xms32m -Xmx256m"
