#!/usr/bin/env python3
import json
import sys

try:
    input_data = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
    sys.exit(1)

tool_name = input_data.get("tool_name", "")
tool_input = input_data.get("tool_input", {})
command = tool_input.get("command", "")

# Only validate git commit commands
if tool_name != "Bash" or "git commit" not in command:
    sys.exit(0)

# Check if Claude author is present
if '--author="Claude <noreply@anthropic.com>"' not in command:
    reason = """❌ Missing Claude author

Commits must be attributed to Claude:
  --author="Claude <noreply@anthropic.com>"

Add to your command:
  git commit --author="Claude <noreply@anthropic.com>" -m "..."

Examples:
  ✅ git commit --author="Claude <noreply@anthropic.com>" -m "feat: add feature"
  ✅ git commit -m "fix: bug fix" --author="Claude <noreply@anthropic.com>"

Invalid:
  ❌ git commit -m "feat: add feature" (missing author)
  ❌ --author="Your Name <email>" (wrong author)

💡 All Claude Code commits must use the Claude author."""

    output = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason
        }
    }
    print(json.dumps(output))
    sys.exit(0)

# Allow the command
sys.exit(0)
