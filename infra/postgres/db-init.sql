-- Идемпотентная подготовка Postgres прод-стенда (сервис db-init в infra/docker-compose.prod.yml).
-- Выполняется при каждом `up`, поэтому работает и на свежем томе, и на существующем pgdata, где
-- docker-entrypoint-initdb.d (init.sql) уже никогда не запустится.
--   psql -v ON_ERROR_STOP=1 -f db-init.sql   (PGHOST/PGUSER/PGPASSWORD/PGDATABASE=darumen и KEYCLOAK_DB_PASSWORD — из окружения)

-- 1. Схемы и расширения БД darumen — то же, что infra/postgres/init.sql (dev-стек), но повторно безопасно
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE SCHEMA IF NOT EXISTS refdata;
CREATE SCHEMA IF NOT EXISTS gold;
CREATE SCHEMA IF NOT EXISTS journal;
CREATE SCHEMA IF NOT EXISTS intake;
CREATE SCHEMA IF NOT EXISTS wolverine;

-- 2. Роль и БД Keycloak. Пароль читается из окружения (\getenv), в командную строку и лог не попадает;
--    ALTER ROLE при каждом запуске применяет смену KEYCLOAK_DB_PASSWORD в .env.
\getenv kc_password KEYCLOAK_DB_PASSWORD
\if :{?kc_password}
  SELECT length(:'kc_password') = 0 AS kc_password_empty \gset
\else
  \set kc_password_empty true
\endif
\if :kc_password_empty
  DO $$ BEGIN RAISE EXCEPTION 'db-init: KEYCLOAK_DB_PASSWORD не задан'; END $$;
\endif

SELECT 'CREATE ROLE keycloak LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'keycloak') \gexec
ALTER ROLE keycloak WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'kc_password';
SELECT 'CREATE DATABASE keycloak OWNER keycloak' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'keycloak') \gexec
-- В БД keycloak ходит только сама роль keycloak (и суперпользователь darumen — для бэкапов и восстановления)
REVOKE ALL ON DATABASE keycloak FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE keycloak TO keycloak;
