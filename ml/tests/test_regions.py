import pytest

from darumen.intake.regions import REGIONS, to_kato


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("Oбласть Жетісу", "33"),  # Latin O
        ("Область ?лытау", "62"),  # broken character
        ("Oбласть Ұлытау", "62"),
        ("Алматы г.а.", "75"),
        ("г. Астана", "71"),
        ("г. Шымкент", "79"),
        ("Алматинская область", "19"),
        ("Северо-Казахстанская область", "59"),
        ("Западно-Казахстанская область", "27"),
        ("Область Абай", "10"),
        ("750000000", "75"),
        ("10", "10"),
        ("Алматы облысы", "19"),
        ("г. Астана (действовавший до 23.03.2019)", "71"),
        ("Южно-Казахстанская область", "61"),  # legacy region, now 61 + 79
        ("", None),
        (None, None),
        ("Ташкент", None),
        ("99", None),
    ],
)
def test_to_kato(value, expected):
    assert to_kato(value) == expected


def test_twenty_regions():
    assert len(REGIONS) == 20
