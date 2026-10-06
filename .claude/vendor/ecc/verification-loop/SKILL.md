---
name: verification-loop
description: Run a phased verification of a Claude Code session's work — build, type check, lint, tests, generated code, security grep, and diff review — then produce a PASS/FAIL verification report. Use when verifying work after completing a feature or refactor, before creating a PR, or when quality gates must pass.
license: MIT
metadata:
  origin: ECC (adapted for banking-go; run from /verify-done)
---

# Verification Loop Skill

A comprehensive verification system for Claude Code sessions in banking-go. It is run by `/verify-done` together with
`.claude/vendor/superpowers/verification-before-completion/SKILL.md`: every phase below must actually run, and its
command + output is the evidence. Never report a phase as PASS without running it.

`go.work` has no root module, so `go build ./...` / `go test ./...` from the repo root fail. Use the Makefile targets.

## When to Use

Invoke this skill:
- After completing a feature or significant code change
- Before creating a PR
- When you want to ensure quality gates pass
- After refactoring

## Verification Phases

### Phase 1: Build Verification
```bash
make build 2>&1 | tail -30        # build-go (every workspace module) + build-web (pnpm -r build)
```

If build fails, STOP and fix before continuing (`/build-fix`).

### Phase 2: Type Check / Vet
```bash
set -o pipefail
make vet 2>&1 | tail -30                                   # go vet every module
npx -y pnpm@12.9.1 -r typecheck 2>&1 | tail -30            # tsc --noEmit per web package
```

Report all errors. Fix them before continuing.

### Phase 3: Lint Check
```bash
make lint 2>&1 | tail -50   # golangci-lint v2 per module (depguard, gosec...) + buf lint + eslint/prettier + tsc
```

Never silence a linter (`//nolint`, eslint-disable, config edits) to pass this phase.

### Phase 4: Test Suite
```bash
make test 2>&1 | tail -50                       # Go unit tests (all modules) + vitest, no Docker
go test -race -count=1 ./pkg/... ./services/core/... ./services/public-api/... \
  ./services/admin-api/... ./services/mocks/... 2>&1 | tail -30   # same as CI (-race)
make test-integration 2>&1 | tail -50           # when integration-tagged tests exist (needs Docker)
make e2e 2>&1 | tail -50                        # when apps/* UI changed
```

Report:
- Total tests: X
- Passed: X
- Failed: X
- Skipped: X (any new skip must have a recorded reason — constitution II.4)
- Coverage: report only for touched packages (`go test -cover <pkg>`); the repo has no coverage threshold

### Phase 5: Generated Code
```bash
make gen-check 2>&1 | tail -30   # protobuf (pkg/gen) + OpenAPI (services/*/api/openapi) match the committed files
```

### Phase 6: Security Scan
```bash
# Secrets (same tool and version as CI)
docker run --rm -v "$PWD:/repo" -w /repo \
  -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
  zricethezav/gitleaks:v8.30.0 git /repo --redact --exit-code 1

# Debug output left behind
git diff main...HEAD -U0 -- '*.go' | grep -nE '^\+.*(fmt\.Print|log\.Print|println\()' | head -10
git diff main...HEAD -U0 -- apps packages | grep -nE '^\+.*console\.log' | head -10

# Money as float / decimals
git diff main...HEAD -U0 -- '*.go' '*.ts' '*.tsx' '*.sql' | grep -nE '^\+.*(float64|float32|numeric\(|parseFloat|toFixed)' | head -10
```

### Phase 7: Diff Review
```bash
# Show what changed on the branch
git diff --stat main...HEAD
git diff main...HEAD --name-only
```

Review each changed file for:
- Unintended changes, or files outside the task's scope / "Hands off" list
- Missing error handling
- Potential edge cases (idempotent replay, `unknown` partner result, lock ordering)
- Edited generated files, lockfiles or merged migrations (must not happen)

## Output Format

After running all phases, produce a verification report:

```
VERIFICATION REPORT
==================

Build:      [PASS/FAIL]
Vet/Types:  [PASS/FAIL] (X errors)
Lint:       [PASS/FAIL] (X issues)
Tests:      [PASS/FAIL] (X/Y passed; integration: ran/not applicable; e2e: ran/not applicable)
Generated:  [PASS/FAIL]
Security:   [PASS/FAIL] (X issues)
Diff:       [X files changed]

Overall:   [READY/NOT READY] for PR

Issues to Fix:
1. ...
2. ...
```

## Continuous Mode

For long sessions, re-run the relevant phases after each task (WIP = 1) rather than only at the end:

```markdown
Set a mental checkpoint:
- After completing each task
- Before marking a task "done" (evidence = command + output)
- Before moving to the next task

Run: Phases 1-4 for the touched modules; the full loop runs in /verify-done
```
