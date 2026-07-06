from data_agent.validator import validate_opengym_json


def test_valid_empty():
    result = validate_opengym_json({
        "version": 1,
        "exportedAt": "2026-07-06T12:00:00Z",
        "settings": {},
        "workoutPlans": [],
        "workoutSessions": []
    })
    assert result.valid
    assert len(result.errors) == 0
    assert len(result.warnings) == 0


def test_valid_session():
    data = {
        "version": 1,
        "exportedAt": "2026-07-06T12:00:00Z",
        "settings": {},
        "workoutPlans": [],
        "workoutSessions": [{
            "date": "2026-07-06T12:00:00Z",
            "planName": "Test",
            "weekNumber": 1,
            "exercises": [{
                "name": "Squat",
                "sets": [{"reps": 10, "weight": 50.0, "rpe": 7, "note": None}],
                "note": None
            }]
        }]
    }
    result = validate_opengym_json(data)
    assert result.valid
    assert len(result.warnings) == 0


def test_missing_version():
    result = validate_opengym_json({})
    assert not result.valid
    assert any("version" in e for e in result.errors)


def test_set_reps_missing():
    data = {
        "version": 1, "exportedAt": "x", "settings": {},
        "workoutPlans": [],
        "workoutSessions": [{
            "date": "x", "planName": "x",
            "exercises": [{"name": "x", "sets": [{}]}],
            "weekNumber": 1
        }]
    }
    result = validate_opengym_json(data)
    assert not result.valid


def test_warning_for_zero_reps_no_note():
    data = {
        "version": 1, "exportedAt": "x", "settings": {},
        "workoutPlans": [],
        "workoutSessions": [{
            "date": "x", "planName": "x",
            "exercises": [{"name": "x", "sets": [{"reps": 0, "weight": 50.0, "rpe": None, "note": None}]}],
            "weekNumber": 1
        }]
    }
    result = validate_opengym_json(data)
    assert result.valid
    assert any("0 reps" in w.lower() or "reps is 0" in w.lower() for w in result.warnings)


def test_warning_for_zero_weight_no_note():
    data = {
        "version": 1, "exportedAt": "x", "settings": {},
        "workoutPlans": [],
        "workoutSessions": [{
            "date": "x", "planName": "x",
            "exercises": [{"name": "x", "sets": [{"reps": 10, "weight": 0.0, "rpe": None, "note": None}]}],
            "weekNumber": 1
        }]
    }
    result = validate_opengym_json(data)
    assert result.valid
    assert any("weight is 0" in w.lower() for w in result.warnings)


def test_zero_values_with_note_no_warning():
    data = {
        "version": 1, "exportedAt": "x", "settings": {},
        "workoutPlans": [],
        "workoutSessions": [{
            "date": "x", "planName": "x",
            "exercises": [{"name": "x", "sets": [{"reps": 0, "weight": 0.0, "rpe": None, "note": "To prepardness"}]}],
            "weekNumber": 1
        }]
    }
    result = validate_opengym_json(data)
    assert result.valid
    # No warning about missing note since note exists
    zero_reps_warnings = [w for w in result.warnings if "reps is 0 with no note" in w]
    assert len(zero_reps_warnings) == 0


def test_workout_session_missing_date():
    data = {
        "version": 1, "exportedAt": "x", "settings": {},
        "workoutPlans": [],
        "workoutSessions": [{"planName": "x", "exercises": [], "weekNumber": 1}]
    }
    result = validate_opengym_json(data)
    assert not result.valid
    assert any("date" in e for e in result.errors)


def test_invalid_rpe_range():
    data = {
        "version": 1, "exportedAt": "x", "settings": {},
        "workoutPlans": [],
        "workoutSessions": [{
            "date": "x", "planName": "x",
            "exercises": [{"name": "x", "sets": [{"reps": 10, "weight": 50.0, "rpe": 11, "note": None}]}],
            "weekNumber": 1
        }]
    }
    result = validate_opengym_json(data)
    assert result.valid
    assert any("rpe" in w and "11" in w for w in result.warnings)


def test_not_dict():
    result = validate_opengym_json("not a dict")
    assert not result.valid


def test_to_dict():
    v = validate_opengym_json({"version": 1, "exportedAt": "", "settings": {}, "workoutPlans": [], "workoutSessions": []})
    d = v.to_dict()
    assert "valid" in d
    assert "errors" in d
    assert "warnings" in d
