import pytest

dg = pytest.importorskip("dagster")


def test_definitions_expose_the_full_lineage():
    from darumen.lakehouse.gold import BUILDERS
    from darumen.orchestration.definitions import defs

    graph = defs.resolve_asset_graph()
    keys = {key.to_user_string() for key in graph.get_all_asset_keys()}
    assert {"silver", "refdata", "models", "published"} <= keys
    assert set(BUILDERS) <= keys
    assert dg.AssetKey("refdata") in graph.get(dg.AssetKey("queue_daily")).parent_keys
    assert dg.AssetKey("models") in graph.get(dg.AssetKey("published")).parent_keys
