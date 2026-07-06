@echo off
setlocal enabledelayedexpansion

:: Load .env if it exists and GEMINI_API_KEY is not already set
if not defined GEMINI_API_KEY (
    if exist "%~dp0data_agent\.env" (
        for /f "tokens=*" %%a in ('type "%~dp0data_agent\.env"') do (
            set "line=%%a"
            if "!line:~0,14!"=="GEMINI_API_KEY=" (
                set "GEMINI_API_KEY=!line:~14!"
            )
        )
    )
)

:: Check if key is set
if not defined GEMINI_API_KEY (
    echo Error: GEMINI_API_KEY is not set.
    echo.
    echo Copy data_agent\.env.example to data_agent\.env and add your key.
    echo Get a key at: https://aistudio.google.com/app/apikey
    exit /b 1
)

:: Pass through to the CLI
python -m data_agent convert %*
