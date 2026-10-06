#!/bin/bash
# PreToolUse (Edit|Write): chặn sửa file cấm. Khóa mềm, không phải cơ chế bảo mật.
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
FILE_PATH="${FILE_PATH//\\//}"
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
REL="${FILE_PATH#"$ROOT"/}"

# File secret: chặn .env, .env.local, .env.production... nhưng vẫn cho sửa .env.example
if [[ "$FILE_PATH" =~ (^|/)\.env(\..+)?$ ]] && [[ "$FILE_PATH" != *.env.example ]]; then
  echo "Blocked: $FILE_PATH là file secret" >&2
  exit 2
fi

# Code sinh ra (chỉ sửa qua `make gen`), lockfile, hạ tầng prod, digest do bot quản lý
PROTECTED_PATTERNS=(".git/" "pkg/gen/" "api/openapi/" ".pb.go" "pnpm-lock.yaml" "go.sum" "go.work.sum" "infra/prod/" "deploy/releases/")
for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "Blocked: $FILE_PATH matches protected pattern '$pattern' (code sinh ra: dùng make gen; infra/prod, deploy/releases: chỉ qua pipeline)" >&2
    exit 2
  fi
done

# Migration đã có trên main: chỉ được thêm file mới, không sửa file cũ
if [[ "$REL" =~ ^services/[^/]+/migrations/.+ ]] && git -C "$ROOT" cat-file -e "main:$REL" 2>/dev/null; then
  echo "Blocked: $REL đã merge vào main. Tạo migration mới (expand → deploy → contract), không sửa migration cũ." >&2
  exit 2
fi

# Khóa foundation: chỉ sửa được khi /foundation đã tạo file mở khóa
if [[ "$FILE_PATH" == *"docs/foundation/"* ]] && [[ ! -f "$ROOT/.claude/foundation.unlock" ]]; then
  echo "Blocked: docs/foundation/ đang khóa. Muốn đổi core thì chạy /foundation update <phần> (cần ADR và user duyệt)." >&2
  exit 2
fi

# Khóa version đã release: docs/features/<feature>/<vN>/... chỉ đọc khi vN đã "released"
if [[ "$FILE_PATH" =~ docs/features/([^/]+)/(v[0-9]+)/ ]]; then
  FJ="$ROOT/docs/features/${BASH_REMATCH[1]}/feature.json"
  if [[ -f "$FJ" ]] && [[ "$(jq -r --arg v "${BASH_REMATCH[2]}" '.versions[$v].status // ""' "$FJ")" == "released" ]]; then
    echo "Blocked: ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} đã release, không sửa. Muốn thay đổi thì tạo version mới qua /brainstorm (nâng cấp)." >&2
    exit 2
  fi
fi
exit 0
