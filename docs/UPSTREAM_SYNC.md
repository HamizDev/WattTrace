# WattTrace maintenance and manual upstream synchronization

WattTrace's primary branch is `main`. MiniWatts remains the upstream project,
regardless of whether GitHub treats the repository as a fork or standalone.
Keep Git history, LICENSE, NOTICE and upstream attribution intact.

- Origin: https://github.com/HamizDev/WattTrace
- Upstream: https://github.com/ResistanceTo/MiniWatts
- Upstream branch: `master`
- Latest upstream commit included when this guide was written (2026-11-24):
  `0b519fda61dfd7b766d4be05fdaa2114f295d5e4`.

## Manual workflow (Git Bash on Windows, or Terminal on macOS)

For a fresh checkout:

```bash
git clone https://github.com/HamizDev/WattTrace.git
cd WattTrace
git remote add upstream https://github.com/ResistanceTo/MiniWatts.git
```

For an existing checkout, inspect `git remote -v` and add upstream only if missing.
Fetch without importing upstream release tags, since WattTrace has its own versioning:

```bash
git switch main
git pull --ff-only origin main
git fetch --no-tags upstream
git log --oneline main..upstream/master
```

If the log is empty and upstream/master is an ancestor of main, no integration is needed.
Otherwise review the changes first, and use a fresh synchronization branch:

```bash
git switch -c sync/miniwatts-YYYYMMDD main
git merge --no-ff upstream/master
````

Resolve conflicts carefully. Preserve WattTrace bundle IDs, app group, Watch target,
branding/icons, device profiles, analysis, export and diagnostic features; do not
blindly prefer either side. Run all regression tests and the full build on macOS,
or push the integration branch and open a pull request to main for GitHub Actions.
Use a merge commit (not squash or rebase) to retain upstream ancestry. Never force
push main or reset it to upstream/master. Only publish a new version after CI
passes and the maintainer requests publication. Existing release tags are immutable.

Direct main pushes do not trigger the existing Build workflow; use PR checks or a
manual workflow run. Published preview releases remain distinct from stable releases.

## Before leaving the GitHub fork network

GitHub's self-service detach operation may discard repository metadata, including
PRs and issue history, and is irreversible. The Git-tracked archive in this
repository contains pre-detachment PR descriptions and release descriptions/asset
inventories only; it is not a backup of comments, workflows, or binary release assets.
Keep a local mirror of the Git repository and a separate copy of release assets if
those must be retained. Verify branches, tags, default branch, releases and CI after
any repository migration. Do not delete and recreate the repository simply to detach.

Reference: https://docs.github.com/en/pull-requests/how-tos/work-with-forks/detaching-a-fork
