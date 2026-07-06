"""
Deterministic normalizer for workout set data.

Parses raw values from the ADK transform agent into clean, import-safe
values for the OpenGym backup JSON schema.

All functions accept raw strings/numbers/None and return clean typed values.
"""

import re
from typing import Any


def normalize_reps(raw: Any) -> tuple[int, str | None]:
    """Parse reps value. Returns (int_reps, note_for_original_text).

    Handles:
    - Plain integer: "10" -> (10, None)
    - With suffix: "10 ES", "12 ea", "15 each side" -> (int, "original text")
    - Percentage: "8" from "8 ES" -> (8, "8 ES")
    - Non-numeric: "To prepardness", "-", "" -> (0, "original text")
    - None -> (0, None)
    """
    if raw is None or str(raw).strip() == "":
        return (0, None)
    s = str(raw).strip().lower()
    try:
        return (int(float(s)), None)
    except ValueError:
        pass
    # "10 ES" / "12 ea" / "15 each side" / "20 ES"
    m = re.match(r'^(\d+)\s*(?:es|ea|each\s+side|reps?)?$', s)
    if m:
        return (int(m.group(1)), str(raw).strip())
    # Starts with a number
    m2 = re.match(r'^(\d+)', s)
    if m2:
        return (int(m2.group(1)), str(raw).strip())
    # Everything else
    return (0, str(raw).strip())


def normalize_weight(raw: Any) -> tuple[float, str | None]:
    """Parse weight value. Returns (float_weight, note_for_original_text).

    Handles:
    - Plain number: "50" -> (50.0, None), "50.5" -> (50.5, None)
    - With kg/lbs suffix: "50 kg", "50.5kg" -> (50.0, None)
    - "5x2" style: -> (5.0, "5x2")  # weight per dumbbell, note the original
    - Non-numeric: "To prepardness", "-", "" -> (0.0, "original text")
    - None -> (0.0, None)
    """
    if raw is None or str(raw).strip() == "":
        return (0.0, None)
    s = str(raw).strip().lower().replace("kg", "").replace("lbs", "").strip()
    try:
        return (float(s), None)
    except ValueError:
        pass
    # "5x2" style (weight x reps embedded)
    m = re.match(r'^(\d+(?:\.\d+)?)\s*x\s*(\d+)$', s)
    if m:
        return (float(m.group(1)), str(raw).strip())
    return (0.0, str(raw).strip())


def normalize_rpe(raw: Any) -> int | None:
    """Parse RPE value. Returns int 1-10 or None.

    Handles:
    - "RPE 7" -> 7
    - "7" -> 7
    - "" -> None
    - None -> None
    - Invalid (non-1-10) -> None
    """
    if raw is None or str(raw).strip() == "":
        return None
    s = str(raw).strip().lower().replace("rpe", "").strip()
    try:
        v = int(float(s))
        if 1 <= v <= 10:
            return v
    except ValueError:
        pass
    return None


def normalize_set(raw_set: dict) -> dict:
    """Normalize a single set dict with 'reps', 'weight', 'rpe', 'note' keys.

    Returns a clean dict guaranteed to be import-safe.
    """
    note_parts = []

    reps, reps_note = normalize_reps(raw_set.get("reps"))
    if reps_note:
        note_parts.append(f"reps: {reps_note}")

    weight, weight_note = normalize_weight(raw_set.get("weight"))
    if weight_note:
        note_parts.append(f"weight: {weight_note}")

    rpe = normalize_rpe(raw_set.get("rpe"))

    existing_note = raw_set.get("note") or ""
    if existing_note and isinstance(existing_note, str):
        note_parts.append(existing_note)

    full_note = "; ".join(note_parts) if note_parts else None

    return {
        "reps": reps,
        "weight": weight,
        "rpe": rpe,
        "note": full_note,
    }


def expand_sets_column(raw: Any) -> int:
    """Number of set-groups this row represents (from a 'Sets' column).

    Returns at least 1. A value like "3" means the row describes 3 sets.
    """
    if raw is None or str(raw).strip() == "":
        return 1
    try:
        v = int(float(str(raw).strip()))
        return max(1, v)
    except ValueError:
        return 1
