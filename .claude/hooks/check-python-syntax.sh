#!/bin/bash
# PostToolUse hook: syntax-check Python scripts under Resolver/Scripts/Resolve/ after Edit/Write/MultiEdit.
# There is no test suite for the Python side, so a syntax error would otherwise only surface
# at runtime inside a live DaVinci Resolve session.
input="$(cat)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty')"

case "$file_path" in
  */Resolver/Scripts/Resolve/*.py)
    if ! error_output="$(python3 -m py_compile "$file_path" 2>&1)"; then
      reason="Syntax error in $file_path (no test suite covers the Python side):
${error_output}"
      jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
    fi
    ;;
esac
