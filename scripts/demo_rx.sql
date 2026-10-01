-- Demo prescriptions for the local "Proverka recepta" page (portal files return 404).
-- All codes start with demo_; numbers are made up, not MZ RK statistics.
-- Remove later:  DROP TABLE IF EXISTS gold.rx_weekly, gold.rx_nosology_monthly, gold.rx_mnn, gold.drug_programs;
-- Real data (make data + make publish) replaces these tables.
BEGIN;
CREATE SCHEMA IF NOT EXISTS gold;
DROP TABLE IF EXISTS gold.rx_weekly, gold.rx_nosology_monthly, gold.rx_mnn, gold.drug_programs;

CREATE TEMP TABLE demo_catalog (nosology_id text, category_id text, program_id text, drug_mnn_id text,
                                per_week int, p50 float8, share float8) ON COMMIT DROP;
INSERT INTO demo_catalog VALUES
  ('demo_n1', 'demo_c1', 'demo_p1', 'demo_m11', 120, 3.0, 0.95),
  ('demo_n1', 'demo_c1', 'demo_p1', 'demo_m12',  60, 6.0, 0.90),
  ('demo_n1', 'demo_c1', 'demo_p1', 'demo_m13',  25, 12.0, 0.80),
  ('demo_n2', 'demo_c2', 'demo_p1', 'demo_m21',  80, 2.0, 0.97),
  ('demo_n2', 'demo_c2', 'demo_p1', 'demo_m22',  40, 9.0, 0.55),  -- shortage signal: share drops in last 4 weeks
  ('demo_n3', 'demo_c3', 'demo_p2', 'demo_m31',  30, 5.0, 0.90),
  ('demo_n3', 'demo_c3', 'demo_p2', 'demo_m32',  22, 4.0, 0.92);

-- 20 weeks ending last week; small deterministic wobble instead of random
CREATE TEMP TABLE demo_weeks ON COMMIT DROP AS
SELECT c.*, k,
       (date_trunc('week', current_date) - make_interval(weeks => k))::date AS week,
       greatest(0, round(c.per_week * (1 + 0.12 * sin(k * 1.7 + length(c.drug_mnn_id)))))::bigint AS issued,
       c.share - CASE WHEN c.share < 0.7 AND k <= 4 THEN 0.2 ELSE 0 END AS s,
       round((c.p50 * (1 + 0.1 * cos(k * 1.3)))::numeric, 1)::float8 AS med
FROM demo_catalog c, generate_series(1, 20) AS k;

CREATE TABLE gold.rx_weekly AS
SELECT week, 'unknown'::text AS region_kato, drug_mnn_id, issued,
       round(issued * s)::bigint AS fulfilled,
       round(round(issued * s) * CASE WHEN p50 <= 6 THEN 0.95 ELSE 0.7 END)::bigint AS fulfilled_14d,
       med AS fill_days_p50, round((med * 2.4)::numeric, 1)::float8 AS fill_days_p90,
       (issued - round(issued * s))::bigint AS gap
FROM demo_weeks;

CREATE TABLE gold.rx_nosology_monthly AS
SELECT date_trunc('month', week)::date AS month, nosology_id, category_id,
       sum(issued)::bigint AS issued, count(DISTINCT drug_mnn_id)::bigint AS mnn_count,
       sum(round(issued * s))::bigint AS fulfilled,
       sum(round(round(issued * s) * CASE WHEN p50 <= 6 THEN 0.95 ELSE 0.7 END))::bigint AS fulfilled_14d,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY med) AS fill_days_p50,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY med * 2.4) AS fill_days_p90
FROM demo_weeks GROUP BY 1, 2, 3;

CREATE TABLE gold.rx_mnn AS
SELECT drug_mnn_id, nosology_id, category_id,
       (sum(issued) * 52 / 20)::bigint AS issued_12m,
       (sum(round(issued * s)) * 52 / 20)::bigint AS fulfilled_12m,
       max(p50) AS fill_days_p50
FROM demo_weeks GROUP BY 1, 2, 3;

CREATE TABLE gold.drug_programs AS
SELECT DISTINCT nosology_id, category_id, program_id, 12::bigint AS specs, 9::bigint AS active_specs,
       5::bigint AS products, 1500.0::float8 AS unit_price_p50, date_trunc('week', current_date)::date AS snapshot_date
FROM demo_catalog;

CREATE INDEX IF NOT EXISTS gold_rx_weekly_idx ON gold.rx_weekly (drug_mnn_id, week);
CREATE INDEX IF NOT EXISTS gold_rx_nosology_monthly_idx ON gold.rx_nosology_monthly (nosology_id, month);
CREATE INDEX IF NOT EXISTS gold_rx_mnn_idx ON gold.rx_mnn (nosology_id, drug_mnn_id);
CREATE INDEX IF NOT EXISTS gold_drug_programs_idx ON gold.drug_programs (nosology_id);
COMMIT;

SELECT 'rx_weekly' AS table, count(*) FROM gold.rx_weekly
UNION ALL SELECT 'rx_nosology_monthly', count(*) FROM gold.rx_nosology_monthly
UNION ALL SELECT 'rx_mnn', count(*) FROM gold.rx_mnn
UNION ALL SELECT 'drug_programs', count(*) FROM gold.drug_programs;
