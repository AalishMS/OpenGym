"""
FastAPI backend for spreadsheet-to-OpenGym conversion.
POST /convert - upload .xlsx/.csv file, returns validated OpenGym backup JSON.
"""

import os
import tempfile
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .pipeline import run_pipeline

app = FastAPI(title="OpenGym Spreadsheet Converter")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/convert")
async def convert(file: UploadFile = File(...)):
    ext = Path(file.filename).suffix.lower()
    if ext not in (".xlsx", ".xls", ".csv"):
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type: {ext}. Accepted: .xlsx, .xls, .csv",
        )

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
    try:
        content = await file.read()
        tmp.write(content)
        tmp.close()

        result = run_pipeline(tmp.name)

        if "error" in result and ("json" not in result or result.get("json") is None):
            raise HTTPException(status_code=422, detail=result["error"])

        return result
    finally:
        os.unlink(tmp.name)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
