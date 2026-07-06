# OpenGym Spreadsheet Converter

An AI-powered pipeline that converts `.xlsx` and `.csv` workout spreadsheets into OpenGym backup JSON using Google ADK (Agent Development Kit) and Gemini 2.0 Flash Lite.

This is the capstone AI agent component of the OpenGym project. The Flutter tracker app uploads a spreadsheet to this server, the agents inspect and transform the data, and the result is imported into the app through the existing backup system.

## How It Works

```
Spreadsheet (.xlsx / .csv)
       │
       ▼
┌─────────────────────────────┐
│  read_spreadsheet() tool    │  ← pandas + openpyxl
│  returns: headers, sample   │
│  rows, raw_grid (irregular) │
└─────────────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│  mapping_agent (Gemini)     │  ← produces MappingPlan
│  - identifies workout blocks│     (Pydantic schema)
│  - finds header rows        │
│  - maps columns to roles    │
└─────────────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│  transform_agent (Gemini)   │  ← writes pandas code
│  - generates extraction     │
│    script                   │
│  - calls run_transform_code │
│  - iterates on failure      │
└─────────────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│  normalizer.py              │  ← deterministic cleanup
│  - cleans reps, weight, RPE │     of ambiguous values
│  - preserves originals as   │
│    notes                    │
└─────────────────────────────┘
       │
       ▼
┌─────────────────────────────┐
│  validator.py               │  ← schema enforcement
│  - checks required fields   │
│  - warns on edge cases      │
└─────────────────────────────┘
       │
       ▼
   OpenGym Backup JSON
```

## Quick Start

### Prerequisites

- Python 3.12+
- A Gemini API key (get one at [Google AI Studio](https://aistudio.google.com/))

### Installation

```bash
# Install dependencies
pip install -r data_agent/requirements.txt

# Set your API key
echo "GEMINI_API_KEY=your_key_here" > .env
```

### Start the Server

```bash
uvicorn data_agent.main:app --host 0.0.0.0 --port 8000
```

### Connect from OpenGym

1. Open the OpenGym app
2. Go to **Settings → Spreadsheet Import**
3. Enter the server URL:
   - `http://10.0.2.2:8000` (Android emulator)
   - `http://localhost:8000` (iOS simulator)
   - `http://<your-ip>:8000` (physical device on same network)
4. Tap **Connect**, pick a `.xlsx` or `.csv` file, then **Convert**
5. Preview the parsed sessions and tap **Import**

## CLI Usage

For headless conversion without the Flutter app:

```bash
# Basic conversion, JSON to stdout
python -m data_agent convert sample.xlsx

# Pretty-print output
python -m data_agent convert sample.xlsx --pretty

# Write to file
python -m data_agent convert sample.xlsx -o output.json

# With explicit API key
python -m data_agent convert sample.xlsx --pretty --key "$GEMINI_API_KEY"
```

Without an API key, the CLI returns a placeholder JSON — useful for testing the pipeline wiring.

## API Reference

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check — returns `{"status": "ok"}` |
| `POST` | `/convert` | Upload `.xlsx`/`.csv` file, receive validated JSON |

### POST /convert

**Request:** `multipart/form-data` with a `file` field containing the spreadsheet.

**Response (success):**
```json
{
  "json": {
    "version": 1,
    "exportedAt": "2026-07-06T12:00:00Z",
    "settings": {},
    "workoutPlans": [],
    "workoutSessions": [...]
  },
  "warnings": ["...ambiguous values noted..."],
  "_validation_errors": []
}
```

**Response (no API key / placeholder):**
```json
{
  "json": { "...placeholder..." },
  "warnings": ["No GEMINI_API_KEY set. ADK conversion skipped."]
}
```

## Project Structure

```
data_agent/
├── __init__.py       — Package init
├── __main__.py       — `python -m data_agent` entry
├── agent.py          — Two Gemini ADK agents
│   ├── mapping_agent    — Spreadsheet layout analysis
│   └── transform_agent  — Pandas code generation
├── pipeline.py       — Orchestrates: agent → normalize → validate
├── tools.py          — Agent tools
│   ├── read_spreadsheet  — File structure inspection
│   └── run_transform_code — Safe subprocess execution
├── schemas.py        — Pydantic models (MappingPlan, Block, etc.)
├── normalizer.py     — Clean reps/weight/RPE with note preservation
├── validator.py      — OpenGym JSON schema enforcement
├── convert.py        — CLI tool for headless conversion
├── main.py           — FastAPI server with /convert and /health
├── .env.example      — Template environment file
├── requirements.txt  — Python dependencies
└── tests/
    ├── test_reader.py       — Spreadsheet reading tests
    ├── test_normalizer.py   — Value normalization tests
    ├── test_validator.py    — Schema validation tests
    └── test_integration.py  — Full pipeline fallback tests
```

## Running Tests

```bash
# From the project root (gymapp-offline/)
python -m pytest data_agent/tests -v

# Run a specific test file
python -m pytest data_agent/tests/test_normalizer.py -v
python -m pytest data_agent/tests/test_validator.py -v
```

Tests cover:
- Reading `.xlsx` and `.csv` files with and without irregular layouts
- Normalization of reps ("10 ES", "12 ea", fractional, non-numeric)
- Normalization of weight ("50 kg", "50.5", "5x2", empty)
- Normalization of RPE ("RPE 7", "7.5", "11", invalid)
- Schema validation (valid data, missing fields, wrong types, edge cases)
- Pipeline behavior when API key is missing (graceful placeholder fallback)
- Reader-normalizer chain integration

## AI Agent Design

### Agents

Two Gemini agents work sequentially using Google ADK:

**Mapping Agent** (`mapping_agent`)
- **Model:** `gemini-2.0-flash-lite`
- **Tool:** `read_spreadsheet` — inspects file structure without loading full contents into context
- **Output:** Structured `MappingPlan` via Pydantic schema
- **Behavior:** Identifies workout blocks, header rows, column roles, forward-fill columns, and ignored columns. Handles multi-sheet files and sheets that are pure glossaries.

**Transform Agent** (`transform_agent`)
- **Model:** `gemini-2.0-flash-lite`
- **Tool:** `run_transform_code` — executes generated pandas script in isolated subprocess
- **Context:** Receives the mapping plan from the previous step as state
- **Behavior:** Writes a self-contained pandas script, runs it, iterates on errors until success

### Safety & Guardrails

- The Gemini API key stays on the server — never exposed to the mobile app
- Generated code runs in a subprocess with a 60-second timeout
- Deterministic normalizer runs after model output, not before
- Schema validator catches structural issues before they reach the app
- All warnings are surfaced to the user before destructive import

## Sample Files

Sample spreadsheets are in `sample_excel_workouts/` at the project root:

- `Training - Suyog Man Singh.xlsx` — Multi-sheet coach template with irregular layouts
- `Introductory Programme.xlsx` — Beginner program with structured layout

These sample files are included for testing and demo purposes.
