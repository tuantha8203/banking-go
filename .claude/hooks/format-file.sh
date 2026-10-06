#!/bin/bash
# PostToolUse (Edit|Write): format file vừa sửa. Lỗi format không chặn AI.
FILE=$(jq -r '.tool_input.file_path // empty')
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then exit 0; fi
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
case "$FILE" in
  */pkg/gen/*|*.pb.go|*/api/openapi/*) exit 0 ;;
  *.go) command -v gofmt >/dev/null && gofmt -w "$FILE" ;;
  *.ts|*.tsx|*.js|*.jsx|*.css|*.json)
    [ -x "$ROOT/node_modules/.bin/prettier" ] && "$ROOT/node_modules/.bin/prettier" --write "$FILE" >/dev/null 2>&1 ;;
esac
exit 0
