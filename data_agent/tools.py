"""
Tools for the OpenGym import agent.

read_spreadsheet: opens a .csv/.xlsx/.xls file and returns a compact
description of its structure (headers, dtypes, row counts, a few sample
rows per sheet) so the LLM can reason about column mapping WITHOUT the
whole file being dumped into context.
"""

import os
import pandas as pd


def read_spreadsheet(file_path: str) -> dict:
    """Inspects a workout spreadsheet and returns its structure.

    Reads a .csv, .xlsx, or .xls file and returns, for each sheet: row
    count, column count, header names, inferred dtypes, and up to 5
    sample rows. Does NOT return the full file contents -- use this to
    understand the shape of the data before deciding how to map columns
    to the OpenGym schema.

    Args:
        file_path: Absolute or relative path to the spreadsheet file on disk.

    Returns:
        A dict with either an "error" key describing what went wrong, or
        a "sheets" key mapping sheet name -> {row_count, column_count,
        headers, dtypes, sample_rows}.
    """
    if not os.path.exists(file_path):
        return {"error": f"File not found: {file_path}"}

    ext = os.path.splitext(file_path)[1].lower()

    try:
        if ext == ".csv":
            sheets_raw = {"default": pd.read_csv(file_path)}
        elif ext in (".xlsx", ".xls"):
            xls = pd.ExcelFile(file_path)
            sheets_raw = {
                name: pd.read_excel(xls, sheet_name=name) for name in xls.sheet_names
            }
        else:
            return {"error": f"Unsupported file extension: {ext}"}
    except Exception as e:
        return {"error": f"Failed to read file: {e}"}

    sheets = {}
    for name, df in sheets_raw.items():
        # Drop fully-empty rows/cols that Excel exports often leave behind
        df = df.dropna(how="all").dropna(axis=1, how="all")
        sample = df.head(5).fillna("").astype(str)
        headers = [str(c) for c in df.columns]

        sheet_info = {
            "row_count": int(len(df)),
            "column_count": int(len(df.columns)),
            "headers": headers,
            "dtypes": {str(col): str(dtype) for col, dtype in df.dtypes.items()},
            "sample_rows": sample.to_dict(orient="records"),
        }

        # Heuristic: if most headers are pandas' "Unnamed: N" placeholder, row 0
        # is almost certainly NOT the real header row (common in hand-built coach
        # templates with day-of-week blocks, multi-row headers, merged cells, etc).
        # In that case also hand back a raw, header-less grid so the caller (the
        # LLM) can visually locate the real structure instead of trusting pandas.
        unnamed_ratio = sum(1 for h in headers if h.startswith("Unnamed:")) / max(len(headers), 1)
        if unnamed_ratio > 0.3:
            raw = pd.read_excel(file_path, sheet_name=name, header=None) if ext != ".csv" \
                else pd.read_csv(file_path, header=None)
            raw = raw.fillna("").astype(str)
            sheet_info["irregular_layout_warning"] = (
                "Most headers came back as 'Unnamed: N', meaning row 0 is probably "
                "not the real header row. This sheet may have multiple header rows, "
                "day-of-week block separators, or merged cells. Use raw_grid below "
                "to visually locate the actual structure instead of relying on 'headers'. "
                "Row indices in raw_grid are 0-indexed and match the RAW sheet exactly "
                "(nothing dropped) -- use these indices, not indices from 'sample_rows', "
                "when referring to row positions."
            )
            sheet_info["raw_grid"] = raw.values.tolist()

        sheets[name] = sheet_info

    return {"file_path": file_path, "sheets": sheets}


import subprocess
import sys
import json


def run_transform_code(code: str) -> dict:
    """Executes a self-contained Python script that transforms a workout spreadsheet into OpenGym JSON.

    Runs in a fresh subprocess (pandas/openpyxl available) so the script can read the
    actual spreadsheet file directly from disk. The script's ENTIRE responsibility is
    to print the final OpenGym JSON object as its last, and only, line of stdout
    (e.g. `print(json.dumps(result))`) -- any other prints will break JSON parsing here.

    Args:
        code: A complete, self-contained Python script (as a string) to execute.

    Returns:
        On success: {"success": True, "json": <parsed OpenGym JSON object>}.
        On failure: {"success": False, "error": str, "stdout": str, "stderr": str} --
        use stdout/stderr to fix the script and call this tool again.
    """
    try:
        proc = subprocess.run(
            [sys.executable, "-c", code],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Script timed out after 60 seconds.", "stdout": "", "stderr": ""}

    if proc.returncode != 0:
        return {
            "success": False,
            "error": f"Script exited with code {proc.returncode}.",
            "stdout": proc.stdout,
            "stderr": proc.stderr,
        }

    stdout = proc.stdout.strip()
    try:
        parsed = json.loads(stdout)
    except json.JSONDecodeError as e:
        return {
            "success": False,
            "error": f"stdout was not valid JSON: {e}",
            "stdout": proc.stdout,
            "stderr": proc.stderr,
        }

    return {"success": True, "json": parsed}