"""
Full pipeline: read spreadsheet -> ADK convert -> normalize -> validate -> return OpenGym JSON.
"""

import asyncio
import json
import os
import re
from datetime import datetime

from .tools import read_spreadsheet
from .normalizer import normalize_set
from .validator import validate_opengym_json


def _build_placeholder(file_path: str, sheet_info: dict) -> dict:
    return {
        "version": 1,
        "exportedAt": datetime.utcnow().isoformat() + "Z",
        "settings": {},
        "workoutPlans": [],
        "workoutSessions": [],
    }


def run_pipeline(file_path: str) -> dict:
    if not os.path.exists(file_path):
        return {"error": f"File not found: {file_path}"}

    sheet_info = read_spreadsheet(file_path)
    if "error" in sheet_info:
        return {"error": sheet_info["error"]}

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        placeholder = _build_placeholder(file_path, sheet_info)
        return {
            "json": placeholder,
            "warnings": [
                "No GEMINI_API_KEY set. ADK conversion skipped. "
                "Set GEMINI_API_KEY env or pass --key to enable real conversion.",
                f"File '{file_path}' has {len(sheet_info.get('sheets', {}))} sheet(s) ready for ADK processing."
            ],
        }

    try:
        result = asyncio.run(_run_adk_pipeline(file_path))
        return result
    except Exception as e:
        return {
            "error": f"ADK conversion failed: {e}",
            "json": _build_placeholder(file_path, sheet_info),
            "warnings": [f"ADK error: {e}. Returning placeholder."],
        }


async def _run_adk_pipeline(file_path: str) -> dict:
    from google.adk.runners import Runner
    from google.adk.sessions import InMemorySessionService
    from google.genai.types import Content, Part

    from .agent import root_agent

    session_service = InMemorySessionService()

    runner = Runner(
        agent=root_agent,
        app_name="opengym_import",
        session_service=session_service,
    )

    session_service.create_session(
        app_name="opengym_import",
        user_id="cli",
        session_id="default",
    )

    message = Content(role="user", parts=[Part(text=file_path)])

    full_response = ""
    async for event in runner.run_async(
        user_id="cli",
        session_id="default",
        new_message=message,
    ):
        if event.content and event.content.parts:
            for part in event.content.parts:
                if part.text:
                    full_response += part.text

    json_match = re.search(r'(\{.*\}|\[.*\])', full_response, re.DOTALL)
    if json_match:
        try:
            json_data = json.loads(json_match.group(1))
            validation = validate_opengym_json(json_data)
            return {
                "json": json_data,
                "warnings": validation.warnings,
                "_validation_errors": validation.errors,
            }
        except json.JSONDecodeError:
            pass

    return {
        "error": "ADK response was not valid JSON",
        "json": _build_placeholder(file_path, {}),
        "warnings": [f"Raw response preview: {full_response[:500]}"],
    }
