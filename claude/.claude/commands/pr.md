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
- Title: imperative, under 70 characters.
- Changes: bullet list focused on the *why* and user-visible impact, not a line-by-line *what*.
- Breaking Changes: leave the empty checkbox if none; otherwise list each.
- How to Reproduce: shell commands a reviewer can run to validate the change locally. Replace `hoge` with the real commands.
- TODO: list real follow-ups; remove the section entirely if none.

Delivery (so the user can copy-paste verbatim without markdown-render breakage):
- **Always** write the final PR description to `.git/PR_BODY.md` (raw markdown, no surrounding fence) using the Write tool.
- In your chat reply, do NOT paste the body inline (the inner ```bash fence collides with chat rendering). Instead, print only:
  - The absolute path to the file.
  - A short one-line summary.
  - Copy hints, e.g. `cat .git/PR_BODY.md | xclip -selection clipboard` (or `| wl-copy` on Wayland), and `gh pr create --title "<title>" --body-file .git/PR_BODY.md` (do NOT run `gh pr create` yourself unless the user explicitly asks).

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
