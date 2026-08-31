#!/bin/bash
# PreToolUse hook: require confirmation before directly editing project.pbxproj.
# This file is normally only machine-edited via sed in Resolver/deploy.sh (version bump) —
# manual edits are easy to corrupt.
input="$(cat)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

case "$file_path" in
  */Resolver.xcodeproj/project.pbxproj)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: "project.pbxproj is normally only machine-edited via sed in Resolver/deploy.sh (version bump). Manual edits are easy to corrupt — confirm this is intentional."
      }
    }'
    ;;
esac
