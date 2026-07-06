#!/bin/bash
# Load .env if it exists and GEMINI_API_KEY is not already set
if [ -z "$GEMINI_API_KEY" ] && [ -f "$(dirname "$0")/data_agent/.env" ]; then
    export $(grep -v '^#' "$(dirname "$0")/data_agent/.env" | xargs)
fi

if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY is not set."
    echo ""
    echo "Copy data_agent/.env.example to data_agent/.env and add your key."
    echo "Get a key at: https://aistudio.google.com/app/apikey"
    exit 1
fi

python -m data_agent convert "$@"
