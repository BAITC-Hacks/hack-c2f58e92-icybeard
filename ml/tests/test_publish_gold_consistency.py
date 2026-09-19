"""5.13: чистая проверка согласованности публикации без Postgres/ClickHouse. PG_TABLES — таблица
Постгреса -> parquet-источник в lakehouse; часть источников (gold/*.parquet) собирается билдерами
из gold.BUILDERS, часть — отдельными моделями (forecast/los/simulate/access index), которые не
проходят через build_gold. Явно перечисляем, какой стем какому билдеру принадлежит (один билдер
может писать несколько parquet, например vac_refusals -> *_by_reason и *_by_contraindication), чтобы
поймать класс бага «таблицу публикуем, а строить её больше некому» (или наоборот)."""
from pathlib import Path

import pandas as pd

from darumen.lakehouse.gold import BUILDERS
from darumen.lakehouse.publish import PG_TABLES, streams_frame
from darumen.models.streams import Stream

# gold/<stem>.parquet -> ключ в gold.BUILDERS, который его пишет (см. вызовы _write(con, out, "<stem>", ...))
# Только стемы, которые реально встречаются как источник в статическом PG_TABLES (gold.queue_daily /
# gold.throughput_4w публикуются отдельно, динамически, внутри publish_postgres — их сюда не берём, иначе
# test_stem_to_builder_map_has_no_stale_entries ругался бы на несуществующую в PG_TABLES запись).
STEM_TO_BUILDER = {
    "admissions_monthly": "admissions_monthly",
    "rx_weekly": "rx_weekly",
    "rx_nosology_monthly": "rx_nosology_monthly",
    "rx_mnn": "rx_mnn",
    "drug_programs": "drug_programs",
    "staffing_by_region": "staffing_by_region",
    "vac_refusals_by_reason": "vac_refusals",
    "vac_refusals_by_contraindication": "vac_refusals",
    "onco_late": "onco_late",
    "equipment_by_region": "equipment",
    "equipment_by_organization": "equipment",
}
# gold/<stem>.parquet, что публикуются, но собираются не в gold.py, а отдельными моделями/пайплайнами —
# для них проверка BUILDERS не применима, перечисляем как известное исключение, а не молча пропускаем
KNOWN_NON_GOLD_BUILDER_SOURCES = {
    "forecasts",           # darumen.models.forecast
    "access_index",        # darumen.models.index / simulate
    "redistribution_q1",   # darumen.models.simulate
    "los_by_profile",      # darumen.models.los
    "rx_fill_by_mnn",      # darumen.models.rx_fill
}


def _gold_stem(source: str) -> str | None:
    path = Path(source)
    if path.parts[0] != "gold":
        return None
    return path.stem


def test_every_pg_table_backed_by_a_gold_builder_or_a_known_model_source():
    seen_gold_stems = set()
    for pg_name, (source, *_rest) in PG_TABLES.items():
        stem = _gold_stem(source)
        if stem is None:
            continue  # refdata.* — не из gold
        seen_gold_stems.add(stem)
        if stem in KNOWN_NON_GOLD_BUILDER_SOURCES:
            continue
        builder_key = STEM_TO_BUILDER.get(stem)
        assert builder_key is not None, (
            f"{pg_name}: gold/{stem}.parquet публикуется, но не сопоставлен ни одному билдеру "
            f"в STEM_TO_BUILDER — если он собирается новым билдером, добавь запись; если он больше "
            f"не собирается — уберите публикацию"
        )
        assert builder_key in BUILDERS, (
            f"{pg_name}: gold/{stem}.parquet ждёт билдер '{builder_key}', "
            f"которого больше нет в gold.BUILDERS"
        )


def test_stem_to_builder_map_has_no_stale_entries():
    """Обратная проверка: каждая запись STEM_TO_BUILDER всё ещё используется каким-то PG_TABLES-источником
    и её билдер всё ещё существует — иначе карта тихо расходится с кодом и перестаёт что-либо ловить."""
    published_gold_stems = {_gold_stem(source) for source, *_ in PG_TABLES.values()}
    published_gold_stems.discard(None)
    for stem, builder_key in STEM_TO_BUILDER.items():
        assert stem in published_gold_stems, f"{stem}: в STEM_TO_BUILDER, но никем из PG_TABLES не публикуется"
        assert builder_key in BUILDERS, f"{stem}: ссылается на несуществующий билдер '{builder_key}'"


def test_streams_frame_shapes_stream_registry_for_gold_streams_table():
    stream = Stream(
        stream_id="er_visits_daily", title="Обращения в приёмный покой", table="er_visits_daily",
        time_col="day", y_col="visits", entity=("region_kato", "mo_key"), grain="day",
        peer_group=(), forecast={"horizons": [7, 30]}, anomaly={},
    )
    frame = streams_frame({"er_visits_daily": stream})
    assert len(frame) == 1
    row = frame.iloc[0]
    assert row["stream_id"] == "er_visits_daily"
    assert row["title"] == "Обращения в приёмный покой"
    assert row["grain"] == "day"
    assert row["gold_table"] == "er_visits_daily"
    assert row["entity_keys"] == "region_kato,mo_key"
    assert row["horizons"] == "7,30"


def test_streams_frame_of_empty_registry_is_an_empty_frame_not_a_crash():
    frame = streams_frame({})
    assert isinstance(frame, pd.DataFrame)
    assert len(frame) == 0
