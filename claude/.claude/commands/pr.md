---
description: Generate a PR description (English, raw markdown) from current branch vs main.
---

Generate a Pull Request description for the current branch.

Steps:
1. Determine the base branch (default `main`; fall back to `master` if `main` is missing).
2. `git fetch origin <base>` (best effort), then read `git log <base>..HEAD --stat`, `git diff <base>...HEAD --stat`, and inspect changed files as needed.
3. Synthesize the description from the actual code changes — do NOT just paraphrase commit messages.

Output rules:
- Output **English**.
- Output **raw markdown** verbatim (no surrounding code fence, no commentary before/after).
- Title: imperative, under 70 characters.
- Changes: bullet list focused on the *why* and user-visible impact, not a line-by-line *what*.
- Breaking Changes: leave the empty checkbox if none; otherwise list each.
- How to Reproduce: shell commands a reviewer can run to validate the change locally. Replace `hoge` with the real commands.
- TODO: list real follow-ups; remove the section entirely if none.

Template (fill in and emit verbatim):

# Title

## 🔄 Changes


## ⚠️  Breaking Changes
- [ ]

## 🔍  How to Reproduce
```bash
hoge
```

## Notes
### TODO:
- [ ] hoge
