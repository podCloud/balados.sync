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

# Only process git commit commands
if tool_name != "Bash" or "git commit" not in command:
    sys.exit(0)

# Vérifier si --author est déjà présent
if "--author" in command:
    sys.exit(0)  # L'utilisateur a déjà spécifié un auteur

# Injecter l'auteur Claude après "git commit"
modified_command = command.replace(
    "git commit",
    'git commit --author="Claude <noreply@anthropic.com>"',
    1
)

# Retourner la commande modifiée
output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "commandModification": {
            "toolInput": {
                "command": modified_command
            }
        }
    }
}
print(json.dumps(output))
sys.exit(0)
