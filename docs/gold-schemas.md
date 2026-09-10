# Схемы витрин gold

Единый источник схем для задач T0.7, T1.1 и T2.1. Витрины считаются Dagster‑активами в `ml/lakehouse/`, хранятся в Parquet на MinIO и публикуются: ряды и аналитика в ClickHouse, справочники и таблицы для API в PostgreSQL. Имена, типы и ключи ниже обязательны; добавлять колонки можно, переименовывать и менять смысл нельзя без правки этого файла.

Общие правила:
- Ключи регионов: `region_kato` строка из двух цифр (`10` … `79`). Организации: `mo_code` строка из четырёх символов ИС БГ. Профили коек: `profile_code` строка (`021`, `DH` …).
- Даты: `day` тип DATE, `week` DATE понедельника, `month` DATE первого числа.
- Ожидание считается в календарных днях: `hospitalization_dt::date - registration_dt::date`.
- Все витрины идемпотентны по партиции: пересчёт партиции заменяет её целиком.
- У каждой витрины есть тест на число строк против манифеста и на отсутствие дублей по ключу.

## silver: типизированные наборы

| Таблица | Источник | Ключ | Партиция | Замечания |
|---|---|---|---|---|
| `silver.bg_referrals` | Направления ИС БГ | `hospitalization_code` | `region_kato, month(registration_dt)` | Добавлены `region_kato, mo_code, profile_code, seq_no` из составного кода, `wait_days`, `outcome` ∈ {hospitalized, refused, open}, `is_day_hospital` |
| `silver.bg_waiting` | Ожидающие ИС БГ | `hospitalization_code` | как выше | Даёт `operation_code, operation_name` |
| `silver.bg_er_refusals` | Отказы приёмного покоя | `row_hash` | `region_kato, month(refuse_dt)` | `mo_code` через разрешение названия `org_in`, `attach_mo_code` из `attach_org` |
| `silver.ersb_cases` | Список пролеченных случаев | `row_hash` | `region_kato, year(p_outdate)` | `mo_code` через разрешение названия, `los_days = p_beddayscount`, `profile_code` через справочник профилей |
| `silver.rx_issued`, `silver.rx_fulfilled` | Рецепты | `recipe_id` | `year(recipe_date)` | Регион пока через `polycl_id → refdata.polyclinics`, если справочник дадут |
| `silver.vac_facts`, `silver.vac_refusals` | Вакцинация | `id` | `region_kato, year(vaccination_date)` | |
| `silver.kdu_referrals` | Направления КДУ, выборка | `row_hash` | `month(referral_date)` | Только скачанные части |
| `silver.staffing`, `silver.equipment` | Ставки, медтехника | `post_id`, `identifier` | | Снимки |

## refdata: справочники

| Таблица | Колонки | Источник |
|---|---|---|
| `refdata.regions` | `region_kato string PK, name_ru, name_kz, kato_full string(9), centroid_lat, centroid_lon, population int` | КАТО, stat.gov.kz |
| `refdata.mo_registry` | `mo_code string PK, name_canonical, name_variants array<string>, region_kato, mo_type, subordination, lat, lon, address, valid_from date, valid_to date null` | Направления, медтехника, data.egov, ручные правки стюарда |
| `refdata.bed_profiles` | `profile_code string PK, name_ru, name_kz, is_day_hospital bool, group string` | Направления |
| `refdata.icd10` | `code string PK, name_ru, chapter string, block string` | Открытый справочник |
| `refdata.referral_purposes`, `refdata.finance_sources` | `code string PK, name_ru` | Направления |
| `refdata.mo_peer_groups` | `mo_code PK, peer_group_id string, region_kato, mo_type, size_bucket string` | Считается из `ersb_cases` и `staffing` |

## gold: витрины

### `gold.queue_daily`
Состояние очереди плановой госпитализации по организации и профилю на каждый день. Основа признаков загрузки для M1 и рядов для M2 и M3.

| Колонка | Тип | Определение |
|---|---|---|
| `day` | DATE | календарный день |
| `region_kato` | STRING | |
| `mo_code` | STRING | принимающая организация |
| `profile_code` | STRING | |
| `registered` | INT | направлений зарегистрировано в этот день |
| `hospitalized` | INT | госпитализаций в этот день |
| `refused` | INT | отказов в этот день |
| `queue_len` | INT | направлений со статусом open на конец дня: `registered_cum - hospitalized_cum - refused_cum` |
| `queue_age_p50` | FLOAT | медиана возраста открытых направлений в днях |
| `queue_age_p90` | FLOAT | 90‑й перцентиль возраста открытых направлений |

Ключ: `(day, mo_code, profile_code)`. Партиция: `region_kato, month(day)`. Хранилище: ClickHouse (ряды), Postgres (последние 90 дней для API).

### `gold.throughput_4w`
Пропускная способность и доля отказов за скользящие 28 дней, на каждый день. Признаки M1, вход симулятора M4.

| Колонка | Тип | Определение |
|---|---|---|
| `day` | DATE | день, на который посчитано окно `[day-28, day-1]` |
| `mo_code`, `profile_code` | STRING | |
| `hospitalized_4w` | INT | госпитализаций за окно |
| `registered_4w` | INT | направлений за окно |
| `refused_4w` | INT | отказов за окно |
| `throughput_per_day` | FLOAT | `hospitalized_4w / 28` |
| `refusal_rate_4w` | FLOAT | `refused_4w / nullif(registered_4w, 0)` |
| `wait_p50_4w`, `wait_p90_4w` | FLOAT | квантили `wait_days` по госпитализированным, зарегистрированным в окне |

Ключ: `(day, mo_code, profile_code)`. Окно строго до `day`, чтобы не было утечки в M1.

### `gold.er_visits_daily`
Обращения в приёмный покой без госпитализации, поток `er_visits_daily` для M2 и M3.

| Колонка | Тип | Определение |
|---|---|---|
| `day` | DATE | `refuse_dt::date` |
| `region_kato`, `mo_code` | STRING | организация обращения |
| `visits` | INT | строк |
| `insured_share` | FLOAT | доля `insured = 'Застрахован'` |
| `top_icd_chapter` | STRING | самая частая глава МКБ‑10 за день |

Ключ: `(day, mo_code)`.

### `gold.admissions_monthly`
Госпитализации по региону и профилю по месяцам из списка пролеченных с 2012 года. Поток `admissions_monthly` для M2 на 1–3 месяца, мощность для M4.

| Колонка | Тип | Определение |
|---|---|---|
| `month` | DATE | месяц выписки `p_outdate` |
| `region_kato`, `profile_code` | STRING | |
| `cases` | INT | выписок |
| `bed_days` | INT | сумма `los_days` |
| `los_mean` | FLOAT | средняя длительность |
| `deaths` | INT | исход «Смерть» |
| `mo_count` | INT | организаций с выписками |

Ключ: `(month, region_kato, profile_code)`. Также `gold.admissions_monthly_mo` с тем же набором по `mo_code`.

### `gold.rx_weekly`
Выписанные и обеспеченные рецепты по неделям, региону и МНН. Поток для Medicines Intelligence.

| Колонка | Тип | Определение |
|---|---|---|
| `week` | DATE | понедельник недели `recipe_date` |
| `region_kato` | STRING | регион поликлиники (через справочник, иначе `unknown`) |
| `drug_mnn_id` | STRING | |
| `issued` | INT | выписано |
| `fulfilled` | INT | обеспечено (по `recipe_id` в fulfilled) |
| `fulfilled_14d` | INT | обеспечено в течение 14 дней от выписки |
| `fill_days_p50`, `fill_days_p90` | FLOAT | квантили `recipe_prov_date - recipe_date` |
| `gap` | INT | `issued - fulfilled` |

Ключ: `(week, region_kato, drug_mnn_id)`.

### `gold.lab_weekly`
Направления на КДУ по неделям, принимающей организации и группе услуг. Поток лабораторий.

| Колонка | Тип | Определение |
|---|---|---|
| `week` | DATE | |
| `receiving_mo_code` | STRING | через разрешение названия |
| `service_group` | STRING | первые три символа `service_code` (`B03` лабораторные, `A02` приёмы, `C03` инструментальные) |
| `referrals` | INT | |
| `cancelled` | INT | `referral_cancellation_date` не пусто |

Ключ: `(week, receiving_mo_code, service_group)`.

### `gold.vac_monthly`
| Колонка | Тип | Определение |
|---|---|---|
| `month`, `region_kato`, `mo_code`, `vaccination_plan` | | |
| `doses` | INT | фактов |
| `age_0_1, age_1_6, age_7_17, age_18_59, age_60_plus` | INT | по возрасту |
| `refusals` | INT | из `vac_refusals` по плану, без организации |

### `gold.features_wait`
Обучающая витрина M1: одна строка на направление круглосуточного стационара.

| Колонка | Тип | Источник |
|---|---|---|
| `hospitalization_code` | STRING | ключ |
| `registration_date` | DATE | |
| `region_kato, mo_code, profile_code, referring_mo_code` | STRING | направление |
| `icd_chapter, icd_block` | STRING | refdata.icd10 |
| `referral_purpose, finance_source, territorial_type` | STRING | направление |
| `same_mo` | BOOL | направляющая = принимающая |
| `queue_len, queue_age_p50, queue_age_p90` | | `queue_daily` на `registration_date - 1` |
| `throughput_per_day, refusal_rate_4w, wait_p50_4w, wait_p90_4w` | | `throughput_4w` на `registration_date` |
| `mo_size_bucket, mo_type` | STRING | refdata |
| `dow, week_of_year` | INT | календарь |
| `wait_days` | INT | цель, null если не госпитализирован |
| `refused` | BOOL | цель |
| `within_30` | BOOL | цель: госпитализирован за 30 дней |
| `split` | STRING | `train` (январь–февраль), `test_time` (март), `test_mo` (10 % организаций) |

### `gold.predictions_wait`, `gold.forecasts`, `gold.anomalies`, `gold.access_index`
Выходы моделей для API. `predictions_wait`: `(as_of, mo_code, profile_code, referral_purpose) → p50_days, p90_days, p_within_30, p_refusal, model_version, explanation_json`. `forecasts`: `(stream_id, entity_json, period, horizon) → yhat, lo, hi, model_version`. `anomalies`: `(stream_id, entity_json, period) → observed, expected, score, severity, status`. `access_index`: `(month, region_kato, profile_code) → share_over_30, p90_days, index_value, rank`.

## Проверки качества на каждой витрине
- Число строк по партиции совпадает с ожиданием из манифеста silver.
- Нет дублей по ключу.
- `queue_len >= 0`; `throughput_per_day >= 0`; `refusal_rate_4w` в `[0, 1]`.
- Для `features_wait`: ни один признак не использует данные позже `registration_date - 1` (тест на утечку сравнивает с пересчётом окна).
