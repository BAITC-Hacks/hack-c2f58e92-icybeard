-- Тестовое согласие на запись приёма для стенда: врач больницы пациента запросил, пациент согласился
-- (действует сегодня, на один приём). Пациент — параметр ref, номер из списка «Пациент» на странице скрайба.
-- Если на этого пациента уже есть запрос, ждущий ответа, согласие ставится на него; иначе создаётся новый запрос.
-- Запуск (из корня проекта):
--   docker compose --env-file .env -f infra/docker-compose.yml cp scripts/dev/scribe-consent.sql postgres:/tmp/s.sql
--   docker compose --env-file .env -f infra/docker-compose.yml exec postgres psql -U darumen -d darumen -v ref=SYN-75-028B-381-03 -f /tmp/s.sql
WITH answered AS (
  SELECT chosen->>'requestId' AS request_id FROM journal.decisions
  WHERE subject = 'scribe' AND subject_id = :'ref' AND chosen ? 'requestId'
), pending AS (
  SELECT id FROM journal.decisions
  WHERE subject = 'scribe' AND subject_id = :'ref' AND chosen->>'scribeConsent' = 'requested'
    AND (recorded_at AT TIME ZONE 'Asia/Almaty')::date = (now() AT TIME ZONE 'Asia/Almaty')::date
    AND id::text NOT IN (SELECT request_id FROM answered)
  ORDER BY recorded_at DESC LIMIT 1
), created AS (
  INSERT INTO journal.decisions (id, actor, role, subject, subject_id, chosen, reason, recorded_at, actor_mo_code)
  SELECT gen_random_uuid(), 'doctor1', 'doctor', 'scribe', :'ref',
         jsonb_build_object('scribeConsent', 'requested', 'moCode', split_part(:'ref', '-', 3)),
         'Тестовое согласие для проверки скрайба', now() - interval '1 second', split_part(:'ref', '-', 3)
  WHERE NOT EXISTS (SELECT 1 FROM pending)
  RETURNING id
), request AS (
  SELECT id FROM pending UNION ALL SELECT id FROM created
)
INSERT INTO journal.decisions (id, actor, role, subject, subject_id, chosen, recorded_at)
SELECT gen_random_uuid(), 'citizen1', 'citizen', 'scribe', :'ref',
       jsonb_build_object('scribeConsent', 'granted', 'requestId', id::text), now()
FROM request
RETURNING subject_id AS patient_ref, 'согласие дано' AS status;
