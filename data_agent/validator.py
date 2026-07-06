from dataclasses import dataclass, field
from typing import Any
import json


@dataclass
class ValidationResult:
    valid: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "valid": self.valid,
            "errors": self.errors,
            "warnings": self.warnings,
        }


def validate_opengym_json(data: Any) -> ValidationResult:
    errors: list[str] = []
    warnings: list[str] = []

    if not isinstance(data, dict):
        return ValidationResult(False, errors=["Root must be a JSON object"])

    version = data.get("version")
    if version != 1:
        errors.append(f"version must be 1, got {version}")

    exported_at = data.get("exportedAt")
    if not isinstance(exported_at, str) or not exported_at:
        errors.append("exportedAt must be a non-empty string")

    settings = data.get("settings")
    if not isinstance(settings, dict):
        errors.append("settings must be an object")

    plans = data.get("workoutPlans", [])
    if not isinstance(plans, list):
        errors.append("workoutPlans must be a list")

    sessions = data.get("workoutSessions", [])
    if not isinstance(sessions, list):
        errors.append("workoutSessions must be a list")
        return ValidationResult(False, errors=errors)

    for i, session in enumerate(sessions):
        if not isinstance(session, dict):
            errors.append(f"sessions[{i}]: must be an object")
            continue

        date = session.get("date")
        if not isinstance(date, str) or not date:
            errors.append(f"sessions[{i}]: date must be a non-empty string")

        plan_name = session.get("planName")
        if not isinstance(plan_name, str) or not plan_name:
            errors.append(f"sessions[{i}]: planName must be a non-empty string")

        week_number = session.get("weekNumber")
        if week_number is not None and not isinstance(week_number, int):
            errors.append(f"sessions[{i}]: weekNumber must be an int")

        exercises = session.get("exercises", [])
        if not isinstance(exercises, list):
            errors.append(f"sessions[{i}]: exercises must be a list")
            continue

        for j, exercise in enumerate(exercises):
            if not isinstance(exercise, dict):
                errors.append(f"sessions[{i}].exercises[{j}]: must be an object")
                continue

            if not isinstance(exercise.get("name"), str) or not exercise["name"]:
                errors.append(f"sessions[{i}].exercises[{j}]: name must be a non-empty string")

            for k, set_item in enumerate(exercise.get("sets", [])):
                if not isinstance(set_item, dict):
                    errors.append(f"sessions[{i}].exercises[{j}].sets[{k}]: must be an object")
                    continue

                reps = set_item.get("reps")
                if not isinstance(reps, int):
                    errors.append(f"sessions[{i}].exercises[{j}].sets[{k}]: reps must be an int, got {type(reps).__name__}")

                weight = set_item.get("weight")
                if not isinstance(weight, (int, float)):
                    errors.append(f"sessions[{i}].exercises[{j}].sets[{k}]: weight must be a number, got {type(weight).__name__}")

                rpe = set_item.get("rpe")
                if rpe is not None and not isinstance(rpe, int):
                    errors.append(f"sessions[{i}].exercises[{j}].sets[{k}]: rpe must be null or int")
                elif isinstance(rpe, int) and not (1 <= rpe <= 10):
                    warnings.append(f"sessions[{i}].exercises[{j}].sets[{k}]: rpe {rpe} is outside 1-10 range")

                note_val = set_item.get("note")
                if note_val is not None and not isinstance(note_val, str):
                    errors.append(f"sessions[{i}].exercises[{j}].sets[{k}]: note must be null or string, got {type(note_val).__name__}")

                if isinstance(reps, int) and reps == 0:
                    note = set_item.get("note")
                    if not note:
                        warnings.append(
                            f"sessions[{i}].exercises[{j}].sets[{k}]: reps is 0 with no note explaining original value"
                        )

                if isinstance(weight, (int, float)) and weight == 0:
                    note = set_item.get("note")
                    if not note:
                        warnings.append(
                            f"sessions[{i}].exercises[{j}].sets[{k}]: weight is 0 with no note explaining original value"
                        )

    return ValidationResult(valid=len(errors) == 0, errors=errors, warnings=warnings)
