"""Integration tests for the full data_agent pipeline (without ADK)."""

import csv
import os
import tempfile

from data_agent.pipeline import run_pipeline
from data_agent.tools import read_spreadsheet
from data_agent.normalizer import normalize_set

SAMPLE_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
    "sample_excel_workouts",
)


def test_pipeline_missing_file():
    result = run_pipeline("nonexistent_file.xlsx")
    assert "error" in result
    assert "File not found" in result["error"]


def test_pipeline_no_key_placeholder():
    path = os.path.join(SAMPLE_DIR, "Training - Suyog Man Singh.xlsx")
    result = run_pipeline(path)
    assert "json" in result
    assert "warnings" in result
    assert len(result["warnings"]) > 0
    assert any("No GEMINI_API_KEY set" in w for w in result["warnings"])
    assert any("sheet" in w for w in result["warnings"])
    assert "workoutPlans" in result["json"]
    assert "workoutSessions" in result["json"]
    assert result["json"]["workoutPlans"] == []
    assert result["json"]["workoutSessions"] == []


def test_pipeline_with_csv():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
        writer = csv.writer(f)
        writer.writerow(["Movement", "Sets", "Reps", "Weight"])
        writer.writerow(["Squat", "3", "10", "50"])
        writer.writerow(["Bench Press", "3", "8", "60"])
        writer.writerow(["Deadlift", "3", "5", "100"])
        csv_path = f.name
    try:
        result = run_pipeline(csv_path)
        assert "json" in result
        assert "warnings" in result
        assert result["json"]["workoutPlans"] == []
        assert result["json"]["workoutSessions"] == []
        assert "version" in result["json"]
        assert result["json"]["version"] == 1
        assert "exportedAt" in result["json"]
    finally:
        os.unlink(csv_path)


def test_reader_normalizer_chain():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
        writer = csv.writer(f)
        writer.writerow(["Movement", "Sets", "Reps", "Weight", "RPE", "Note"])
        writer.writerow(["Squat", "3", "10 ES", "50 kg", "RPE 7", "belt"])
        writer.writerow(["Bench", "3", "8", "60.5", "8", ""])
        writer.writerow(["Deadlift", "3", "5", "100", "", "straps"])
        csv_path = f.name
    try:
        sheet_info = read_spreadsheet(csv_path)
        assert "error" not in sheet_info, sheet_info.get("error")
        assert "sheets" in sheet_info
        sheet = list(sheet_info["sheets"].values())[0]
        assert sheet["row_count"] == 3
        sample_rows = sheet["sample_rows"]

        for row in sample_rows:
            name = row.get("Movement", "")
            reps_raw = row.get("Reps", "")
            weight_raw = row.get("Weight", "")
            rpe_raw = row.get("RPE", "")
            note_raw = row.get("Note", "")

            normalized = normalize_set({
                "reps": reps_raw,
                "weight": weight_raw,
                "rpe": rpe_raw,
                "note": note_raw,
            })

            assert isinstance(normalized["reps"], int)
            assert isinstance(normalized["weight"], float)
            assert normalized["rpe"] is None or isinstance(normalized["rpe"], int)

            if name == "Squat":
                assert normalized["reps"] == 10
                assert normalized["weight"] == 50.0
                assert normalized["rpe"] == 7
                assert normalized["note"] is not None
                assert "10 ES" in normalized["note"]
            elif name == "Bench":
                assert normalized["reps"] == 8
                assert normalized["weight"] == 60.5
                assert normalized["rpe"] == 8
            elif name == "Deadlift":
                assert normalized["reps"] == 5
                assert normalized["weight"] == 100.0
                assert normalized["rpe"] is None
                assert normalized["note"] is not None
                assert "straps" in normalized["note"]
    finally:
        os.unlink(csv_path)
