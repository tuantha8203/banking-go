---
name: write-tests
description: Write failing tests for one plan task before implementing it.
disable-model-invocation: true
argument-hint: "[feature] [task-id]"
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
Công cụ: áp dụng `.claude/vendor/superpowers/test-driven-development/SKILL.md` (+ skill testing Go/React trong .claude/skills/ nếu có).
Từ W/plan.md, lấy task $1.
1. Viết test cho tiêu chí của task bằng go test (unit; integration dùng testcontainers với tag `integration`) / Vitest (web). KHÔNG viết code implement.
2. Chạy `make test-one PKG=<./path/pkg> RUN=<TestName>` (Go) hoặc `make test-one WEB=<@banking-go/app> RUN=<tên test>` (web)` cho test mới, xác nhận FAIL đúng lý do, dán output.
3. Commit "test: <task>".
