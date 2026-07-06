"""
Full pipeline: read spreadsheet -> normalize -> validate -> return OpenGym JSON.
"""

import os
from datetime import datetime

from .tools import read_spreadsheet
from .normalizer import normalize_set
from .validator import validate_opengym_json


def run_pipeline(file_path: str) -> dict:
    """
    Run the full conversion pipeline on a spreadsheet file.
    
    Args:
        file_path: Path to .xlsx or .csv file
    
    Returns:
        dict with keys:
          - "json": the OpenGym backup JSON dict (may be partial without ADK)
          - "warnings": list of warning strings
          - "error": error string if something failed (absent on success)
    """
    if not os.path.exists(file_path):
        return {"error": f"File not found: {file_path}"}
    
    sheet_info = read_spreadsheet(file_path)
    if "error" in sheet_info:
        return {"error": sheet_info["error"]}
    
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        placeholder = {
            "version": 1,
            "exportedAt": datetime.utcnow().isoformat() + "Z",
            "settings": {},
            "workoutPlans": [],
            "workoutSessions": [],
        }
        return {
            "json": placeholder,
            "warnings": [
                "No GEMINI_API_KEY set. ADK conversion skipped. "
                "Set the environment variable or pass --key to enable real conversion.",
                f"File '{file_path}' has {len(sheet_info.get('sheets', {}))} sheet(s) ready for ADK processing."
            ],
        }
    
    sheet_count = len(sheet_info.get("sheets", {}))
    return {
        "json": {
            "version": 1,
            "exportedAt": datetime.utcnow().isoformat() + "Z",
            "settings": {},
            "workoutPlans": [],
            "workoutSessions": [],
        },
        "warnings": [
            f"ADK pipeline not yet wired. File has {sheet_count} sheet(s)."
        ],
    }
