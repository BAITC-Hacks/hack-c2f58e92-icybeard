"""4.4: `intake contracts` (list/approve) and `intake reprocess` — the CLI side of turning a draft into
a real contract and re-running a file once its contract exists or changed."""
from pathlib import Path

from darumen.intake.cli import main
from darumen.intake.pipeline import Lakehouse

FIXTURES = Path(__file__).parent / "fixtures" / "intake"


def test_contracts_list_is_empty_and_then_shows_a_draft_after_an_unknown_upload(tmp_path, capsys):
    lake_dir, contracts_dir = tmp_path / "lake", tmp_path / "contracts"
    assert main(["contracts", "list", "--lakehouse", str(lake_dir)]) == 0
    assert "черновиков нет" in capsys.readouterr().out

    assert main(["add", str(FIXTURES / "unknown_schema.csv"), "--contracts", str(contracts_dir),
                "--lakehouse", str(lake_dir), "--no-events"]) == 0
    capsys.readouterr()
    assert main(["contracts", "list", "--lakehouse", str(lake_dir)]) == 0
    assert "unknown_schema" in capsys.readouterr().out


def test_reprocess_loads_a_file_once_its_contract_exists(tmp_path, capsys):
    lake_dir, contracts_dir = tmp_path / "lake", tmp_path / "contracts"
    lake = Lakehouse(lake_dir)
    main(["add", str(FIXTURES / "unknown_schema.csv"), "--contracts", str(contracts_dir), "--lakehouse", str(lake_dir), "--no-events"])
    capsys.readouterr()

    # без контракта reprocess тоже даёт черновик, а не падает
    assert main(["reprocess", str(FIXTURES / "unknown_schema.csv"), "--contracts", str(contracts_dir),
                "--lakehouse", str(lake_dir), "--no-events"]) == 0
    assert "UNKNOWN" in capsys.readouterr().out
    assert not lake.silver("unknown_schema").exists()

    assert main(["contracts", "approve", "unknown_schema", "--contracts", str(contracts_dir), "--lakehouse", str(lake_dir), "--no-events"]) == 0
    out = capsys.readouterr().out
    assert "APPROVED" in out and "исходный файл черновика не найден" in out  # `add`, в отличие от загрузки через консоль, не хранит source_file

    assert main(["reprocess", str(FIXTURES / "unknown_schema.csv"), "--contracts", str(contracts_dir),
                "--lakehouse", str(lake_dir), "--no-events"]) == 0
    assert "LOADED" in capsys.readouterr().out
    assert lake.silver("unknown_schema").exists()
