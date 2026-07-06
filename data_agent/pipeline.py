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

    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
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

    from .agent import mapping_agent, transform_agent

    session_service = InMemorySessionService()
    app_name = "opengym_import"

    async def _run_agent(agent, session_id, message_text, state=None):
        runner = Runner(
            agent=agent,
            app_name=app_name,
            session_service=session_service,
        )
        await session_service.create_session(
            app_name=app_name,
            user_id="cli",
            session_id=session_id,
            state=state,
        )
        msg = Content(role="user", parts=[Part(text=message_text)])
        collected = ""
        json_output = None
        async for event in runner.run_async(
            user_id="cli",
            session_id=session_id,
            new_message=msg,
        ):
            if event.content and event.content.parts:
                for part in event.content.parts:
                    if part.text:
                        collected += part.text
                    elif part.function_call:
                        # Structured output via output_schema arrives as function_call
                        import json as _json
                        fc = part.function_call
                        if hasattr(fc, 'args') and fc.args:
                            try:
                                args_str = _json.dumps(fc.args)
                                if len(args_str) > 20:
                                    json_output = fc.args
                            except Exception:
                                pass
        return collected, json_output

    # Step 1: Mapping agent inspects the spreadsheet
    mapping_text, mapping_structured = await _run_agent(
        mapping_agent, "mapping", file_path
    )
    mapping_plan = mapping_structured or _extract_json(mapping_text)
    if mapping_plan is None:
        return {
            "error": "Mapping agent did not produce valid JSON",
            "json": _build_placeholder(file_path, {}),
            "warnings": [f"Mapping response preview: {mapping_text[:2000]}"],
        }

    # Step 2: Transform agent uses the mapping plan
    transform_text, transform_structured = await _run_agent(
        transform_agent,
        "transform",
        "Transform this spreadsheet into OpenGym backup JSON.",
        state={"mapping_plan": mapping_plan},
    )
    json_data = transform_structured or _extract_json(transform_text)
    if json_data is None:
        return {
            "error": "Transform agent did not produce valid JSON",
            "json": _build_placeholder(file_path, {}),
            "warnings": [f"Transform response preview: {transform_text[:2000]}"],
        }

    validation = validate_opengym_json(json_data)
    return {
        "json": json_data,
        "warnings": validation.warnings,
        "_validation_errors": validation.errors,
    }


def _extract_json(text: str):
    """Extract first JSON object or array from a text response."""
    json_match = re.search(r'(\{.*\}|\[.*\])', text, re.DOTALL)
    if json_match:
        try:
            return json.loads(json_match.group(1))
        except json.JSONDecodeError:
            pass
    return None
