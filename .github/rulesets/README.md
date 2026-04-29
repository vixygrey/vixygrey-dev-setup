# Branch protection rulesets

Version-controlled GitHub repository rulesets for this repo. Each `*.json`
file in this directory is a ruleset spec that can be applied via the GitHub
REST API.

## Files

- [`main.json`](main.json) — protections for the default branch (`main`):
  - Require pull request before merging (squash-merge only, conversation
    resolution required, stale reviews dismissed on new push)
  - Require `ShellCheck` status check to pass, with the branch up to date
  - Block force pushes (`non_fast_forward`) and branch deletion
  - Require linear history (matches the `gh pm` squash-merge workflow)
  - Repo admins bypass the ruleset (for emergency fixes)

Required approving reviews and signed commits are intentionally **not** set
— this is a single-maintainer repo and requiring reviews would self-block.
Add them later if collaborators come on board.

## Apply a ruleset

Create or update the `main` ruleset on the live repo:

```bash
# Create (first time)
gh api repos/:owner/:repo/rulesets \
  --method POST \
  --input .github/rulesets/main.json

# Update (subsequent edits — replace <ID> with the ruleset id)
gh api repos/:owner/:repo/rulesets/<ID> \
  --method PUT \
  --input .github/rulesets/main.json
```

List existing rulesets to find the id:

```bash
gh api repos/:owner/:repo/rulesets
```

## Editing

Edit the JSON, commit on a feature branch, open a PR, and re-apply with
the `PUT` command above after merge. Keep the file as the source of truth
— if the live ruleset drifts (edited via GitHub's UI), re-apply from JSON
to bring it back in line.
