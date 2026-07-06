"""
Structured output schema for the mapping step.

Given the raw structure from read_spreadsheet (headers, sample rows, and --
for irregular sheets -- the full raw grid), the mapping agent's job is to
locate the real header row(s), split the sheet into blocks (e.g. one per
day-of-week), and say which raw column plays which role. This plan is what
the later transform step (pandas code generation) will be driven by, so
row indices here MUST refer to positions in the raw, unmodified grid --
the same one a later `pd.read_excel(path, sheet_name=..., header=None)`
call would produce.
"""

from typing import Optional
from pydantic import BaseModel, Field


class ColumnMapping(BaseModel):
    """Which raw column (by header label) plays which role in one block."""

    exercise_column: str = Field(
        description="Header label of the column containing exercise/movement names."
    )
    sets_column: Optional[str] = Field(
        default=None,
        description="Header label for number-of-sets, if it exists as its own column.",
    )
    reps_column: Optional[str] = Field(
        default=None, description="Header label for reps."
    )
    weight_column: Optional[str] = Field(
        default=None, description="Header label for weight/load used."
    )
    rpe_column: Optional[str] = Field(
        default=None, description="Header label for RPE (rate of perceived exertion), if present."
    )
    note_column: Optional[str] = Field(
        default=None,
        description="Header label for freeform notes / coach's comments, if present.",
    )


class Block(BaseModel):
    """One self-contained workout session within a sheet.

    A single sheet can contain multiple blocks (e.g. one per day-of-week),
    each with its own header row and its own exercise rows.
    """

    block_label: Optional[str] = Field(
        default=None,
        description=(
            "Day-of-week or day label for this block, e.g. 'Sunday' or 'Day 1'. "
            "Null if the whole sheet is a single block with no such label."
        ),
    )
    header_row_index: int = Field(
        description="0-indexed row number, in the raw unmodified grid, containing this block's real column headers."
    )
    data_start_row_index: int = Field(
        description="0-indexed row where this block's exercise data starts."
    )
    data_end_row_index: int = Field(
        description="0-indexed row where this block's exercise data ends (inclusive)."
    )
    column_mapping: ColumnMapping
    forward_fill_columns: list[str] = Field(
        default_factory=list,
        description=(
            "Header labels of columns where blank cells should be filled with the "
            "value from the row above -- e.g. an exercise name that's only written "
            "once, then left blank on subsequent set-group rows for that same exercise."
        ),
    )
    reasoning: str = Field(
        description="Brief explanation of how this block's boundaries and column roles were identified."
    )


class SheetMappingPlan(BaseModel):
    sheet_name: str
    is_workout_data: bool = Field(
        description="False if this sheet isn't workout log data at all (e.g. a pure glossary or one-off maxes sheet)."
    )
    blocks: list[Block] = Field(default_factory=list)
    ignored_columns: list[str] = Field(
        default_factory=list,
        description="Header labels present in the sheet that are NOT part of workout data and should be ignored (e.g. a glossary sidebar column).",
    )


class MappingPlan(BaseModel):
    file_path: str
    sheets: list[SheetMappingPlan]