import duckdb

from darumen.intake.normalize import icd10_canon, mo_name_key, register_udfs

KGP = ('Коммунальное государственное предприятие на праве хозяйственного ведения '
       '"Многопрофильная центральная районная больница Аягозского района" управления здравоохранения области Абай')


def test_mo_name_key_takes_quoted_core():
    assert mo_name_key(KGP) == "многопрофильная центральная районная больница аягозского района"
    assert mo_name_key(' "Медицинский центр ДИАГНОСТ"') == "медицинский центр диагност"


def test_mo_name_key_strips_legal_forms_without_quotes():
    assert mo_name_key("ТОО Cardio tonus") == "cardio tonus"
    assert mo_name_key("КГП на ПХВ Городская больница №4") == "городская больница 4"
    assert mo_name_key("") is None and mo_name_key(None) is None


def test_icd10_canon():
    assert icd10_canon("j03.9") == "J03.9"
    assert icd10_canon(" M54,4 ") == "M54.4"
    assert icd10_canon("С34.1") == "C34.1"  # Cyrillic С
    assert icd10_canon("Острый тонзиллит") is None
    assert icd10_canon(None) is None


def test_udfs_work_in_sql():
    con = duckdb.connect()
    register_udfs(con)
    rows = con.execute(
        "SELECT to_kato(r), mo_name_key(m), icd10_canon(c) FROM (VALUES ('Алматы г.а.', $1, 'j03.9'), (NULL, NULL, NULL)) t(r, m, c)",
        [KGP],
    ).fetchall()
    assert rows[0] == ("75", "многопрофильная центральная районная больница аягозского района", "J03.9")
    assert rows[1] == (None, None, None)
