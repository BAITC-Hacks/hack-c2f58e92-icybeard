import duckdb

from darumen.intake.normalize import icd10_chapter
from darumen.refdata.build import build_refdata, classify_mo


def test_icd10_chapter():
    assert icd10_chapter("J03.9") == "X"
    assert icd10_chapter("C34.1") == "II"
    assert icd10_chapter("D48") == "II" and icd10_chapter("D50") == "III"
    assert icd10_chapter("H25.1") == "VII" and icd10_chapter("H60") == "VIII"
    assert icd10_chapter("S72.0") == "XIX" and icd10_chapter("Z00") == "XXI"
    assert icd10_chapter("nope") is None and icd10_chapter(None) is None


def test_classify_mo():
    assert classify_mo("Городская поликлиника №3") == "polyclinic"
    assert classify_mo("Областной перинатальный центр") == "maternity"
    assert classify_mo("Научно-исследовательский институт кардиологии") == "republican"
    assert classify_mo("Городская больница №1") == "hospital"
    assert classify_mo("Центр психического здоровья") == "center"
    assert classify_mo("Cardio tonus", nomenclature="Клиника") == "hospital"
    assert classify_mo(None) == "other"


def test_registry_from_synthetic_lake(synthetic_lake):
    report = build_refdata(synthetic_lake)
    assert report["tables"]["regions"] == 20
    assert report["tables"]["mo_registry"] == 2
    con = duckdb.connect()
    rows = con.execute(f"SELECT mo_code, name_key, region_kato, mo_type, size_bucket, peer_group_id FROM read_parquet('{synthetic_lake.root}/refdata/mo_registry.parquet') ORDER BY mo_code").fetchall()
    assert rows[0][0] == "00AA" and rows[0][1] == "городская больница 1" and rows[0][2] == "10" and rows[0][3] == "hospital"
    assert rows[0][5] == f"10:hospital:{rows[0][4]}"
    profiles = dict(con.execute(f"SELECT profile_code, name_ru FROM read_parquet('{synthetic_lake.root}/refdata/bed_profiles.parquet')").fetchall())
    assert profiles["021"] == "Терапевтические" and profiles["DH"] == "Дневной стационар"
    index = con.execute(f"SELECT region_kato, name_key, mo_code FROM read_parquet('{synthetic_lake.root}/refdata/mo_name_index.parquet') ORDER BY mo_code").fetchall()
    assert ("10", "городская больница 1", "00AA") in index
    assert report["coverage"]["er_orgs_resolved_to_code"] == 1.0
