import pytest

from darumen.models.train import PARTS, parse_only


def test_only_matches_whole_names():
    assert parse_only("anomaly_labels") == {"anomaly_labels"}
    assert parse_only(" forecast , anomaly ") == {"forecast", "anomaly"}
    assert parse_only(",".join(PARTS)) == set(PARTS)


def test_only_rejects_unknown_parts():
    with pytest.raises(SystemExit, match="waitt"):
        parse_only("waitt")
