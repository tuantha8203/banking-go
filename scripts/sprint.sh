#!/bin/bash
# scripts/sprint.sh — board của sprint đang làm. Nguồn sự thật: tasks.json. Cần jq.
# Dùng: sprint.sh status [--short] | board | next | check [--all] | index
set -euo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ACTIVE_FILE="$ROOT/docs/features/ACTIVE"          # 1 dòng: <feature>/<version>, vd dang-ky-thue-bao/v2
CMD="${1:-status}"; OPT="${2:-}"

if [[ "$CMD" == "index" ]]; then
  OUT="$ROOT/docs/features/INDEX.md"
  {
    echo "# Feature index"; echo
    echo "| Feature | Version hiện tại (prod) | Đang làm | Tóm tắt version hiện tại | Release |"
    echo "|---|---|---|---|---|"
    for f in "$ROOT"/docs/features/*/feature.json; do
      [[ -f "$f" ]] || continue
      jq -r '. as $x | "| [\(.title // .feature)](\(.feature)/README.md) | \(.current // "-") | \(.working // "-") | \((.versions[$x.current // ""].summary) // "-") | \((.versions[$x.current // ""].release) // "-") |"' "$f"
    done
  } > "$OUT"
  echo "Đã ghi ${OUT#"$ROOT"/}"; exit 0
fi

ACT=$( { tr -d '[:space:]' < "$ACTIVE_FILE"; } 2>/dev/null || true)
if [[ -z "$ACT" ]]; then
  if [[ "$CMD" == "status" ]]; then
    [[ "$OPT" == "--short" ]] && echo "no sprint" || echo "Chưa có sprint đang làm (docs/features/ACTIVE trống)."
    exit 0
  fi
  echo "Chưa có docs/features/ACTIVE" >&2; exit 1
fi
W="$ROOT/docs/features/$ACT"
T="$W/tasks.json"
[[ -f "$T" ]] || { echo "Không thấy $T" >&2; exit 1; }

SPRINT=$(jq -r '[.sprints[]? | select(.status=="active")][0].id // empty' "$T")
FILTER='.tasks[]'; [[ -n "$SPRINT" ]] && FILTER=".tasks[] | select(.sprint==\"$SPRINT\")"
cnt() { jq --arg s "$*" "[ $FILTER | select(.status==\$s) ] | length" "$T"; }
TOTAL=$(jq "[ $FILTER | select(.status!=\"dropped\") ] | length" "$T")
DONE=$(cnt done); DOING=$(cnt in-progress); BLOCKED=$(cnt blocked); DROPPED=$(cnt dropped)
CUR=$(jq -r "[ $FILTER | select(.status==\"in-progress\") ][0].id // \"-\"" "$T")
NEXT=$(jq -r --arg s "$SPRINT" '
  (.tasks | map({(.id): .status}) | add) as $st
  | [ .tasks[] | select(($s=="" or .sprint==$s) and .status=="not-started")
      | select((.dependencies // []) | all($st[.]=="done")) ][0].id // "-"' "$T")
NAME="$(jq -r '.feature + " " + .version' "$T")"

case "$CMD" in
  status)
    if [[ "$OPT" == "--short" ]]; then
      echo "$NAME · ${SPRINT:-all} · $DONE/$TOTAL done · doing $CUR · next $NEXT"
    else
      echo "SPRINT: $NAME · sprint ${SPRINT:-all} — $DONE/$TOTAL done, $DOING doing, $BLOCKED blocked, $DROPPED dropped."
      echo "Đang làm: $CUR · Tiếp theo: $NEXT · Board: ${W#"$ROOT"/}/BOARD.md"
      echo "Luật: làm ĐÚNG MỘT task; chỉ chuyển done khi có evidence; không xóa task (bỏ thì 'dropped' + lý do + user duyệt);"
      echo "      chưa được báo sprint xong khi 'scripts/sprint.sh check' còn fail."
    fi ;;
  next) echo "$NEXT" ;;
  board)
    {
      echo "# Board — $NAME — sprint ${SPRINT:-all}"; echo
      echo "Tiến độ: **$DONE/$TOTAL done** · $DOING doing · $BLOCKED blocked · $DROPPED dropped"; echo
      for s in in-progress not-started blocked done dropped; do
        case $s in in-progress) h="Doing";; not-started) h="Todo";; blocked) h="Blocked";; done) h="Done";; dropped) h="Dropped";; esac
        echo "## $h"
        jq -r "$FILTER | select(.status==\"$s\") | \"- [\" + (if .status==\"done\" then \"x\" else \" \" end) + \"] \" + .id + \": \" + .name + (if (.note // \"\") != \"\" then \" — \" + .note else \"\" end)" "$T"
        echo
      done
    } > "$W/BOARD.md"
    echo "Đã ghi ${W#"$ROOT"/}/BOARD.md" ;;
  check)
    SCOPE="$FILTER"; [[ "$OPT" == "--all" ]] && SCOPE='.tasks[]'
    BAD=$(jq -r "[ $SCOPE | select(.status!=\"dropped\") | select(.status!=\"done\" or ((.evidence // \"\") | length)==0) | .id ] | join(\",\")" "$T")
    NOREASON=$(jq -r "[ $SCOPE | select(.status==\"dropped\" and ((.note // \"\") | length)==0) | .id ] | join(\",\")" "$T")
    # Task có trong bản đã commit mà nay biến mất = bị xóa lén
    REL="${T#"$ROOT"/}"; REMOVED=""
    if git -C "$ROOT" cat-file -e "HEAD:$REL" 2>/dev/null; then
      REMOVED=$(jq -rn --argjson old "$(git -C "$ROOT" show "HEAD:$REL" | jq '[.tasks[].id]')" \
                       --argjson new "$(jq '[.tasks[].id]' "$T")" '($old - $new) | join(",")')
    fi
    if [[ -n "$BAD" || -n "$NOREASON" || -n "$REMOVED" ]]; then
      [[ -n "$BAD" ]] && echo "CHƯA XONG (chưa done hoặc thiếu evidence): $BAD" >&2
      [[ -n "$NOREASON" ]] && echo "DROPPED KHÔNG CÓ LÝ DO: $NOREASON" >&2
      [[ -n "$REMOVED" ]] && echo "TASK BỊ XÓA so với commit trước (phải dùng 'dropped', không xóa): $REMOVED" >&2
      exit 1
    fi
    echo "OK: mọi task đã done và có evidence." ;;
  *) echo "Dùng: sprint.sh status [--short] | board | next | check [--all] | index" >&2; exit 2 ;;
esac
