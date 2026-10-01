-- Сброс тестовых маршрутов на локальном стенде: удаляет все события маршрутов (переводы, согласия, сигналы,
-- подтверждения, выписки) и отметки прочтения колокольчика. Аудит (journal.audit), решения симулятора и согласия
-- на запись приёма не трогает. После сброса граждане снова видят исходную очередь, врачи — чистый рабочий список.
-- Запуск (из корня проекта):
--   docker compose --env-file .env -f infra/docker-compose.yml cp scripts/dev/reset-routes.sql postgres:/tmp/r.sql
--   docker compose --env-file .env -f infra/docker-compose.yml exec postgres psql -U darumen -d darumen -f /tmp/r.sql
-- Затем заново: python scripts/dev/seed_routes.py
BEGIN;
DELETE FROM journal.notification_reads;
DELETE FROM journal.decisions WHERE subject = 'route';
COMMIT;
SELECT count(*) AS route_events_left FROM journal.decisions WHERE subject = 'route';
