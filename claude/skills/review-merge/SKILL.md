---
name: review-merge
description: "Review a PR AND merge it if it passes — find the current branch's PR, assess it against a quality rubric (correctness/tests/clean/style/scope), then `gh pr merge --squash --delete-branch`. Use when the user says /review-merge, 'review and merge this PR', 'ship this PR', or asks to merge a pull request. Distinct from /review (review-only, no merge) — review-merge is the merge moment. Use `--no-merge` for review-only."
---

# Review & Merge PR

Review an open PR, assess code quality, and merge if it passes review.

## Trigger

User says `/review-merge` optionally followed by a PR number or URL.

## Process

### 1. Find the PR

- If a PR number or URL is provided, use that
- Otherwise, find the open PR for the current branch: `gh pr list --head $(git branch --show-current) --json number,title,url`
- If no PR found, check for any open PRs in the repo: `gh pr list --json number,title,url`
- If multiple PRs, ask the user which one

### 2. Review the PR

Run these in parallel:
- `gh pr view <number> --json title,body,state,additions,deletions,changedFiles,files`
- `gh pr diff <number>`
- `gh pr checks <number>` (if CI exists)

### 3. Assess Quality

Evaluate the diff against these criteria:
- **Correctness**: Does the code do what the PR title/description says?
- **Tests**: Are there tests? Do they cover the key behaviors?
- **No junk**: No debug logs, commented-out code, scaffold files, or credentials
- **Style**: Follows existing patterns in the codebase
- **Scope**: Changes are focused — no unrelated modifications

### 4. Report

Present a concise verdict:
```
PR #N: <title>
Files: N changed (+additions/-deletions)
<1-3 line summary of what it does>

✓ Correctness — <brief>
✓ Tests — <brief>
✓ Clean — <brief>
[or ✗ with explanation for any failures]

Verdict: MERGE / NEEDS FIXES
```

### 5. Act

- **If MERGE**: Run `gh pr merge <number> --squash --delete-branch`
- **If NEEDS FIXES**: List specific issues. Do NOT merge. Ask user if they want you to fix the issues.

## Options

- `/review-merge` — find and review current branch's PR
- `/review-merge 42` — review PR #42
- `/review-merge --no-merge` — review only, don't merge even if passing
