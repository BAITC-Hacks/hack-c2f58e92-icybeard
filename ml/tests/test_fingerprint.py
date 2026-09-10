from darumen.intake.fingerprint import fingerprint


def test_fingerprint_bom_comma(tmp_path):
    path = tmp_path / "a.csv"
    path.write_bytes("﻿id,name,dt\n1,\"x, y\",2025-01-01\n".encode())
    fp = fingerprint(path)
    assert fp.format == "csv" and fp.encoding == "utf-8" and fp.has_bom
    assert fp.delimiter == "," and fp.header == ("id", "name", "dt") and fp.size_bytes == path.stat().st_size


def test_fingerprint_semicolon_cp1251(tmp_path):
    path = tmp_path / "b.csv"
    path.write_bytes("код;название\n1;Тест\n".encode("cp1251"))
    fp = fingerprint(path)
    assert fp.encoding == "cp1251" and fp.delimiter == ";" and fp.header == ("код", "название")


def test_fingerprint_non_csv(tmp_path):
    path = tmp_path / "c.parquet"
    path.write_bytes(b"PAR1")
    assert fingerprint(path).format == "parquet"
