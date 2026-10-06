# Git Workflow

## Commit Message Format
```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci (Conventional Commits, see `CLAUDE.md`)

Branches: `feat/<feature>-<vN>`, `fix/...`, `chore/...`. Commit only when the repo is in a safe state; never commit secrets.

## Pull Request Workflow

When creating PRs:
1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Ask the user before pushing (`git push` requires approval); never force-push

> The development process (brainstorm → plan → test → implement → review → verify → ship) is defined in `CLAUDE.md`.
