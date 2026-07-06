#!/usr/bin/env python3
"""
CLI tool: convert a workout spreadsheet to OpenGym backup JSON.

Usage:
    python -m data_agent convert sample.xlsx
    python -m data_agent convert sample.csv --pretty
    python -m data_agent convert sample.xlsx -o output.json
"""

import argparse
import json
import sys

from .pipeline import run_pipeline


def main():
    parser = argparse.ArgumentParser(
        description="Convert a workout spreadsheet to OpenGym backup JSON",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python -m data_agent convert sample.xlsx
  python -m data_agent convert sample.xlsx --pretty
  python -m data_agent convert sample.xlsx -o backup.json
  python -m data_agent convert sample.csv --pretty --key "$GEMINI_API_KEY"
        """,
    )
    
    subparsers = parser.add_subparsers(dest="command")
    
    convert_parser = subparsers.add_parser("convert", help="Convert a spreadsheet to OpenGym JSON")
    convert_parser.add_argument("file", help="Path to .xlsx or .csv file")
    convert_parser.add_argument("--pretty", "-p", action="store_true", help="Pretty-print JSON output")
    convert_parser.add_argument("--output", "-o", help="Write JSON to file instead of stdout")
    convert_parser.add_argument("--key", help="Gemini API key (or set GEMINI_API_KEY env var)")
    
    args = parser.parse_args()
    
    if args.command != "convert":
        parser.print_help()
        sys.exit(1)
    
    if args.key:
        import os
        os.environ["GEMINI_API_KEY"] = args.key
        os.environ["GOOGLE_API_KEY"] = args.key
    
    result = run_pipeline(args.file)
    
    if "error" in result:
        print(f"Error: {result['error']}", file=sys.stderr)
        sys.exit(1)
    
    json_data = result["json"]
    warnings = result.get("warnings", [])
    
    indent = 2 if args.pretty else None
    output = json.dumps(json_data, indent=indent, default=str)
    
    if warnings:
        print(f"// Warnings ({len(warnings)}):", file=sys.stderr)
        for w in warnings:
            print(f"//   - {w}", file=sys.stderr)
    
    if args.output:
        with open(args.output, "w") as f:
            f.write(output)
        print(f"Written to {args.output}")
    else:
        print(output)


if __name__ == "__main__":
    main()
