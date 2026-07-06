from google.adk.agents import Agent

from .tools import read_spreadsheet, run_transform_code
from .schemas import MappingPlan

mapping_agent = Agent(
    name="mapping_agent",
    model="gemini-2.0-flash-lite",
    description="Inspects a workout spreadsheet and produces a structured mapping plan of its layout.",
    instruction="""
You are the mapping stage of an OpenGym import pipeline.

1. Call read_spreadsheet on the given file path.
2. For each sheet, work out the real structure and produce a MappingPlan.

Real workout spreadsheets are often NOT clean tables. Watch for:

- "headers" full of "Unnamed: N" -> row 0 is not the real header row. When
  this happens, read_spreadsheet also returns "raw_grid": the full,
  unmodified sheet as a plain grid (0-indexed rows). Read it like a human
  looking at the actual Excel sheet, not like a dataframe. ALL of your row
  indices in the output (header_row_index, data_start_row_index,
  data_end_row_index) must refer to positions in this raw_grid, never to
  "sample_rows" (which come from a cleaned, re-indexed dataframe and will
  NOT line up with raw_grid).

- Day-of-week or day labels (e.g. "Sunday", "Day 1") sitting alone in a row,
  with their OWN header row (e.g. Movement/Sets/Reps) a row or two below.
  Each such label starts a new block -- a separate workout session -- and
  needs its own header_row_index and data range. Find every block in the
  sheet, not just the first one.

- The same exercise name appearing once, then left blank on the rows that
  follow -- those blank rows are additional set-groups for that SAME
  exercise (e.g. Squat: RPE 6 x1x1, RPE 7 x1x3, RPE 5 x2x5 are 3 rows, 1
  exercise). Put the exercise's header label in forward_fill_columns so a
  later step knows to fill it down.

- Sidebar columns unrelated to the workout itself (e.g. "Current Maxes
  estimation", "Important Terms" glossary) that happen to share the sheet.
  List these in ignored_columns, not in any block's column_mapping.

- A sheet might not be workout data at all (pure glossary, one-off maxes
  table). Set is_workout_data to false for those and leave blocks empty.

Be thorough: find every block in every sheet before responding. Explain
your reasoning briefly per block so a human can sanity-check your read of
the layout.
""",
    tools=[read_spreadsheet],
    output_schema=MappingPlan,
    output_key="mapping_plan",
)

transform_agent = Agent(
    name="transform_agent",
    model="gemini-2.0-flash-lite",
    description="Writes and executes pandas code that turns a mapped spreadsheet into OpenGym backup JSON.",
    instruction="""
You are the transform stage of an OpenGym import pipeline.

You are given a mapping plan describing the exact layout of a workout
spreadsheet:

{mapping_plan}

Write ONE self-contained Python script that:
1. Reads mapping_plan["file_path"] directly with pandas (header=None per
   sheet), re-reading the file yourself -- do not assume any data is already
   in memory.
2. Skips sheets where is_workout_data is false.
3. For each block: slice rows data_start_row_index..data_end_row_index
   (inclusive), using header_row_index to get column labels via
   column_mapping.
4. Forward-fill columns listed in forward_fill_columns (blank cells take
   the value from the row above -- this reconstructs exercise names that
   were only written once for a multi-row set-group).
5. Group consecutive rows for the same exercise into one exercise entry
   with a "sets" list. Each row is a set-group: if a sets_column exists and
   parses to N, that row represents N sets. Parse reps/weight as numbers
   where possible; if a cell can't be parsed as a number (e.g. "AMRAP",
   "-", "to prepardness"), put the raw text in that set's "note" field and
   skip building reps/weight for that row rather than crashing.
6. Build the final OpenGym JSON exactly matching this schema:
   - version: 1
   - exportedAt: current UTC ISO 8601 timestamp
   - settings: empty object
   - workoutPlans: empty list
   - workoutSessions: a list of session objects, each with:
     - date: ISO 8601, best guess -- if no real date exists, use a plausible
       placeholder rather than failing
     - planName: block_label if present, else the sheet name
     - weekNumber: 1
     - exercises: a list of exercise objects, each with:
       - name: string
       - sets: a list of {"reps": int, "weight": number, "rpe": int or null, "note": string or null}
       - note: string or null
7. Print ONLY the final JSON object via `print(json.dumps(result))` as the
   very last line of output. No other prints, no markdown fences, nothing
   else on stdout.

Then call run_transform_code with that script as the `code` argument.

If run_transform_code returns success=False, read the "error" and "stderr"
fields, fix the script, and call run_transform_code again. Keep iterating
until it succeeds. Once it succeeds, your final response is the JSON object
from the "json" field -- nothing else.
""",
    tools=[run_transform_code],
    output_key="opengym_json",
)

# SequentialAgent is deprecated in favor of manual orchestration.
# Use these as individual agents; run mapping first, then pass
# output as context to transform in the pipeline.
__all__ = ["mapping_agent", "transform_agent"]