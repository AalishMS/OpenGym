import json
import os
from data_agent.tools import read_spreadsheet

SAMPLE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "sample_excel_workouts")

def test_suyog_file_readable():
    path = os.path.join(SAMPLE_DIR, "Training - Suyog Man Singh.xlsx")
    result = read_spreadsheet(path)
    assert "error" not in result, result.get("error")
    assert "sheets" in result
    assert len(result["sheets"]) > 0

def test_introductory_file_readable():
    path = os.path.join(SAMPLE_DIR, "Introductory Programme.xlsx")
    result = read_spreadsheet(path)
    assert "error" not in result, result.get("error")
    assert "sheets" in result

def test_detects_irregular_layout():
    path = os.path.join(SAMPLE_DIR, "Training - Suyog Man Singh.xlsx")
    result = read_spreadsheet(path)
    for sheet_name, info in result["sheets"].items():
        if info.get("irregular_layout_warning"):
            assert "raw_grid" in info
            return
    # At least one sheet should have irregular layout for this file
    assert any("irregular_layout_warning" in info for info in result["sheets"].values())

def test_invalid_file():
    result = read_spreadsheet("nonexistent_file.xlsx")
    assert "error" in result

def test_csv_file():
    # Create a temp CSV to test CSV reading
    import tempfile
    import csv
    with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
        writer = csv.writer(f)
        writer.writerow(["Movement", "Sets", "Reps"])
        writer.writerow(["Squat", "3", "10"])
        writer.writerow(["Bench", "3", "8"])
        csv_path = f.name
    try:
        result = read_spreadsheet(csv_path)
        assert "error" not in result, result.get("error")
        assert "sheets" in result
    finally:
        os.unlink(csv_path)
