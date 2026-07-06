from data_agent.normalizer import (
    normalize_set, normalize_reps, normalize_weight, normalize_rpe,
    expand_sets_column,
)


def test_reps_basic():
    assert normalize_reps("10") == (10, None)
    assert normalize_reps(10) == (10, None)
    assert normalize_reps("0") == (0, None)


def test_reps_with_suffix():
    result_reps, result_note = normalize_reps("10 ES")
    assert result_reps == 10
    assert result_note is not None

    result_reps, result_note = normalize_reps("12 ea")
    assert result_reps == 12
    assert result_note is not None

    result_reps, result_note = normalize_reps("15 each side")
    assert result_reps == 15
    assert result_note is not None


def test_reps_non_numeric():
    assert normalize_reps("To prepardness") == (0, "To prepardness")
    assert normalize_reps("-") == (0, "-")
    assert normalize_reps("") == (0, None)
    assert normalize_reps(None) == (0, None)


def test_weight_basic():
    assert normalize_weight("50") == (50.0, None)
    assert normalize_weight(50) == (50.0, None)
    assert normalize_weight("50.5") == (50.5, None)
    assert normalize_weight("50 kg") == (50.0, None)
    assert normalize_weight("50.5kg") == (50.5, None)


def test_weight_empty():
    assert normalize_weight("") == (0.0, None)
    assert normalize_weight(None) == (0.0, None)


def test_weight_non_numeric():
    result_val, result_note = normalize_weight("To prepardness")
    assert result_val == 0.0
    assert result_note is not None

    result_val, result_note = normalize_weight("-")
    assert result_val == 0.0
    assert result_note is not None


def test_weight_ambiguous():
    result_val, result_note = normalize_weight("5x2")
    assert result_val == 5.0
    assert result_note == "5x2"

    result_val, result_note = normalize_weight("3 bars")
    assert result_val == 0.0
    assert result_note == "3 bars"


def test_reps_fractional():
    result_reps, result_note = normalize_reps("10.5")
    assert result_reps == 10
    assert result_note is not None
    assert "10.5" in result_note

def test_reps_fractional_integer():
    assert normalize_reps("10.0") == (10, None)

def test_weight_unit_variants():
    assert normalize_weight("50 kgs") == (50.0, None)
    assert normalize_weight("50 kilograms") == (50.0, None)
    assert normalize_weight("50 kilogram") == (50.0, None)
    assert normalize_weight("50 kilos") == (50.0, None)
    assert normalize_weight("50 lbs") == (50.0, None)
    assert normalize_weight("50 pounds") == (50.0, None)
    assert normalize_weight("50lb") == (50.0, None)

def test_rpe():
    assert normalize_rpe("RPE 7") == 7
    assert normalize_rpe("7") == 7
    assert normalize_rpe("rpe 7") == 7
    assert normalize_rpe(None) is None
    assert normalize_rpe("") is None
    assert normalize_rpe("0") is None
    assert normalize_rpe("11") is None
    assert normalize_rpe("not rpe") is None


def test_normalize_set_full():
    result = normalize_set({"reps": "10", "weight": "50", "rpe": "RPE 7", "note": None})
    assert result["reps"] == 10
    assert result["weight"] == 50.0
    assert result["rpe"] == 7
    assert result["note"] is None

def test_normalize_set_decimal_rpe():
    result = normalize_set({"reps": "10", "weight": "50", "rpe": "RPE 7.5", "note": None})
    assert result["rpe"] == 7
    assert result["note"] is not None
    assert "7.5" in result["note"]

def test_normalize_set_non_dict():
    result = normalize_set(None)
    assert result["reps"] == 0
    assert result["weight"] == 0.0
    assert result["rpe"] is None

    result = normalize_set("foo")
    assert result["reps"] == 0
    assert result["weight"] == 0.0
    assert result["rpe"] is None

    result = normalize_set([])
    assert result["reps"] == 0
    assert result["weight"] == 0.0
    assert result["rpe"] is None


def test_normalize_set_with_note():
    result = normalize_set({"reps": "10 ES", "weight": "25", "rpe": ""})
    assert result["reps"] == 10
    assert result["weight"] == 25.0
    assert result["rpe"] is None
    assert result["note"] is not None
    assert "10 ES" in result["note"]


def test_normalize_set_preserves_existing_note():
    result = normalize_set({"reps": "10 ES", "weight": "25", "rpe": "", "note": "slow eccentrics"})
    assert result["note"] is not None
    assert "slow eccentrics" in result["note"]


def test_normalize_set_unknown_values():
    result = normalize_set({"reps": "To prepardness", "weight": "", "rpe": None})
    assert result["reps"] == 0
    assert result["weight"] == 0.0
    assert result["rpe"] is None
    assert result["note"] is not None


def test_expand_sets_basic():
    assert expand_sets_column("3") == 3
    assert expand_sets_column("1") == 1
    assert expand_sets_column("0") == 1  # minimum 1


def test_expand_sets_empty():
    assert expand_sets_column("") == 1
    assert expand_sets_column(None) == 1


def test_expand_sets_non_numeric():
    assert expand_sets_column("AMRAP") == 1
