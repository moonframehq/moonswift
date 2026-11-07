#!/usr/bin/env bash
# Stands in for `claude -p` in `just smoke`, speaking its stream-json. Its first
# edit breaks the app on purpose; only a --resume of the same session fixes it,
# which proves that errors go back to the agent, in the same conversation.
set -euo pipefail
cat > /dev/null

# The limits are what keep an edit from becoming code execution: losing one
# fails the smoke test.
for needed in --restricted --strict-mcp-config dontAsk 'Edit(**/*.luau)' 'Write(**/*.luau)'; do
    [[ " $* " == *" $needed "* ]] || { echo "launched without $needed" >&2; exit 1; }
done
[[ " $* " != *" acceptEdits "* ]] || { echo "launched with acceptEdits" >&2; exit 1; }

file="mods/counter/main.luau"
emit() { printf '%s\n' "$1"; }

emit "shell noise that isn't JSON"
emit '{"type":"system","subtype":"init","session_id":"fake-session"}'
emit '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'"$PWD/$file"'"}}]}}'

if [[ " $* " == *" --resume fake-session "* ]]; then
    mv "$file.good" "$file"
    sed -i '' 's/label = "More"/label = "Agent was here"/' "$file"
    emit '{"type":"assistant","message":{"content":[{"type":"text","text":"Fixed it and renamed the button."}]}}'
else
    cp "$file" "$file.good"
    echo 'return mod {' > "$file"
    emit '{"type":"assistant","message":{"content":[{"type":"text","text":"Renamed the button."}]}}'
fi
emit '{"type":"result","is_error":false,"result":"done"}'
