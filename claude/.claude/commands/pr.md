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
- Wrap the entire PR body in a single outer fenced code block (four backticks `` ```` ``) so the user sees the raw markdown source — including `#`, `##`, `-`, ``` ` ```, `[ ]` — rather than a rendered preview. The four-backtick fence ensures the inner triple-backtick `bash` block (the How-to-Reproduce section) does not break the outer fence.
- The first line of the outer fence must be exactly four backticks on their own line. The line after must literally start with `# ` (hash + space). The closing fence is four backticks on their own line at the very end of the message.
- Do NOT add any commentary, preface, or trailing text outside the outer fence. The outer fence is the entire response.
- Title: imperative, under 70 characters.
- Changes: bullet list focused on the *why* and user-visible impact, not a line-by-line *what*.
- Breaking Changes: leave the empty checkbox if none; otherwise list each.
- How to Reproduce: shell commands a reviewer can run to validate the change locally. Replace `hoge` with the real commands.
- TODO: list real follow-ups; remove the section entirely if none.

Brevity rules — a reviewer must grasp what shipped in **under 30 seconds**:
- Aim for **3–5 bullets total** in `## 🔄 Changes`. Stop adding bullets once the reviewer has enough to approve. If you have more than 5, you are summarising commits — re-synthesise.
- Each bullet ≤ **2 sentences**, ≤ **40 words**. Lead with the user-visible outcome, then the smallest amount of "why" needed to justify it. Cut implementation details unless they change reviewer behaviour (e.g. a non-obvious trade-off, a known edge case).
- Do NOT enumerate every file, function, or constant touched. Do NOT recap the debug journey, abandoned approaches, or things that were "tried and reverted" — those belong in commit messages, not the PR body.
- The first bullet should answer "what does this PR fix / add / change for the user?" in one line. A reviewer skimming should understand the whole PR from bullet #1 alone.
- If a critical caveat exists (perf cost, behaviour change in adjacent flow, follow-up debt), surface it in `## ⚠️  Breaking Changes` or `### TODO:`, not as a sixth Changes bullet.
- Prefer plain prose over bold/italic emphasis. No emoji decoration inside bullets.

Template (the outer fence below is `````` (four backticks); the inner shell block uses three backticks as usual):

````
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
````
