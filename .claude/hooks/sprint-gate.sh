#!/bin/bash
# Stop hook: chỉ chặn khi bật chế độ tự chạy (file .claude/sprint.autopilot).
cat > /dev/null
[[ -f "$CLAUDE_PROJECT_DIR/.claude/sprint.autopilot" ]] || exit 0
if ! OUT=$("$CLAUDE_PROJECT_DIR/scripts/sprint.sh" check 2>&1); then
  NEXT=$("$CLAUDE_PROJECT_DIR/scripts/sprint.sh" next 2>/dev/null || echo "-")
  jq -n --arg r "Sprint chưa xong: $OUT. Làm tiếp task $NEXT (scripts/sprint.sh next). Gặp blocker thì chuyển task sang blocked kèm lý do rồi báo user." \
    '{decision: "block", reason: $r}'
fi
exit 0
