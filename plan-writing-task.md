# Task: write plan.md for wtx

Two parts:

- **Part A — Questions.** Everything I need answered before [plan.md](./plan.md)
  can be written. Answer inline (edit this file), skip freely, or answer in
  conversation. A "no opinion, you decide" is a valid answer and I'll pick a
  default and record it in the plan.
- **Part B — Context.** Everything established so far, so a fresh session can
  start from this file alone.

---

# Part A — Questions

## 1. Intention & audience

1. Is wtx for you alone, or do you intend teammates to use it?
Teammates and maybe some friends

2. If teammates: same OS/editor assumptions (macOS + VSCode), or must it degrade gracefully?
For now same OS/editor assumptions, but later it might be configurable

3. Is it meant to be public on GitHub eventually, or stay a private repo?
Public repo but no distribution plan yet

4. Is "make Claude Code sessions cheap to spin up in isolation" the primary purpose, or is that one use case of a general worktree tool?
Yup, creating parallel claude code implementation tasks in isolation is the main idea, or picking up a worktree from an existing branch

5. Would you still want wtx if you stopped using Claude Code tomorrow?
No idea, irrelevant

6. What's the one-sentence pitch you'd want in the README?
No idea, you come up with this

7. Is there an existing tool this replaces or competes with that you've tried (`git-worktree-cli`, `gwq`, `worktree.nvim`, `git wt` aliases)? Anything you liked or hated about them?
It basically replaces the claude worktree hooks in a more opinionated way that wasn't customisable in claude: for example creating the worktree outside of the repo directory

8. How much do you care about it being *fast* (sub-second) vs. thorough?
Fast is high priority, but not sub second, maybe up to 30-60 seconds is fine if it reduces risks (for example copuing node_modules carries risks I only want to take if installing becomes slow)

## 2. Naming

9. Is `wtx` final, or a working title?
Nothing is ever final. stands for worktree-extended

10. Command invoked as `wtx`, or also aliased shorter (`wt`)?
wtx

11. Any name collision concern on your PATH already?
no

12. Do you want `git wtx <cmd>` to work too (git subcommand style, via a `git-wtx` name)?
nah

13. Subcommand names: `create`/`remove`/`list`, or `new`/`rm`/`ls`, or aliases for both?
new rm/remove ls/list (so both work)

14. Should the worktree directory naming stay `<repo>-<name>` as a sibling, or become configurable (e.g. `../<repo>.worktrees/<name>`)?
start with ../<repo>-worktrees/<name>, but make it configurable

15. Branch name = worktree name always, or should they be independently settable?
same by default, but allow independent branch name via `--branch` flag

## 3. Command surface — create

16. Confirm: `wtx create <name>` and that's the only required arg?
y

17. Should `create` accept an optional base ref (`wtx create foo --from release/2.1`)?
Not explicitly, see next question

18. Should it accept an *existing* branch (`wtx create --branch feature/x` checks out rather than creating)?
It should always check if the branch already exists and if so prompt the user to confirm they intend to "resume" from there (wither in existing worktree or in new worktree with the branch checked out)

19. What if the branch already exists — hard error (current behaviour), or offer to check it out?
Prompt the user to confirm they intend to resume

20. Should the name be auto-generated when omitted (the way `claude -w` did, e.g. `bright-running-fox`)?
no

21. Should there be a `--no-open` flag to skip the editor?
not yet

22. Should there be a `--no-install`/`--no-setup` flag to skip the dependency install?
no

23. Should `create` print the path (current behaviour, enabling `cd "$(wtx create x)"`), or would you rather it print human output and offer `--print-path`?
Not sure, I don't understand usages or intention

24. Should it offer to `cd` you into the worktree in the current shell (requires a shell function wrapper, not just a binary — worth it?)?
no, just print success and path, then exit

25. Should Jira-style names be parsed at all (e.g. `wtx create APP-1234` fetching the ticket title for the branch name)? That would pull in `jira`/MCP dependencies.
no

## 4. Command surface — remove

26. Keep the interactive "uncommitted changes, remove anyway?" prompt, or require `--force`?
print a prompt and exit requiring force

27. Should `remove` also close the VSCode window? (Possible, hacky — needs AppleScript or `code` CLI tricks.)
no for now

28. Keep the "delete the branch only if it's an ancestor of the default branch" rule?
No, this will integrate better with the ls subcommand hopefully, basically allowing global management of worktrees

29. Should `remove` handle "the branch was squash-merged" (ancestor check fails, but the PR is merged)? Detect via `gh pr view --state merged`?
no, it should only care that everything is pushed to a remote

30. Should `wtx remove` with no args remove the worktree you're currently *inside*?
not yet

31. Bulk removal — `wtx remove --merged` to sweep every worktree whose branch is merged?
no

32. Should removal be recoverable at all (e.g. keep the branch by default and only prune the directory)?
branch should be kept no matter what, only worktree and directory should be deleted, this tool is not supposed to manage git flows other than the creation

## 5. Command surface — the third subcommand and beyond

33. What did you have in mind for the third subcommand?
ls

34. If `list`: what columns — path, branch, dirty state, ahead/behind, PR status, last commit date, disk size?
grouped by repo (if possible to find all repos with worktrees), then branch, path, dirty state, ahead/behind, last commit date

35. Should `list` have machine-readable output (`--json`, `--porcelain`) for scripting/statusline use?
nah

36. Interest in `wtx open <name>` (reopen an existing worktree's editor window)?
37. Interest in `wtx cd <name>` / a shell integration to jump between worktrees?
38. Interest in `wtx sync` (rebase every worktree branch onto the latest default branch)?
39. Interest in `wtx prune` (fix git bookkeeping for directories you deleted manually)?
40. Interest in `wtx doctor` (check PATH, `code`, `jq`, config validity)?
41. Interest in `wtx config` (read/write the per-repo config)?
42. Do you want a `wtx exec <name> -- <cmd>` to run a command inside a worktree?
no to all

## 6. Configuration

43. Per-repo config file — do you want one at all, or are per-invocation flags plus smart defaults enough?
just flags and defaults

44. If yes: what format — `.wtxrc` as shell `KEY=value` (sourceable, zero deps), TOML, YAML, or JSON (needs `jq`)?
n

45. Or store config in git itself (`git config wtx.baseRef main`) — no new file, travels with the clone, but per-clone rather than per-repo?
n

46. Should it be committed to the project repo (shared with the team) or gitignored (yours only)? Or support both, layered?
n

47. What must be configurable? My candidates: base ref, setup command, editor command, include-file list, worktree parent directory, post-create hook. Which of these matter, which don't?
For now the ones we already talked about

48. Should `.worktreeinclude` stay a separate file, or fold into the config?
no

49. Default base ref when unconfigured: `origin/HEAD` (auto-detect), `origin/main`, or the currently checked-out branch?
origin/main if it exists, otherwise prompt to use flag

50. Should it fetch before branching every time (current behaviour, adds latency), or only with `--fetch`?
yes but also I like when branches start without an upstream or even better with <remote>/<branch> upstream

51. Setup command default: nothing? Or detect the package manager (`pnpm`/`npm`/`yarn`/`bun`/`cargo`/`uv`) and run its install?
I don't get what the setup in question is

52. Should the setup command run in the VSCode task (visible, current approach) or in the script before opening the window (blocking, but the window is ready when it appears)?
don't get the question

53. Editor: VSCode hardcoded, `$EDITOR`, `$VISUAL`, or a config key? Any interest in Cursor/JetBrains/nvim support?
let's start with vscode hardcoded

54. Should the "start a Claude session in the integrated terminal" behaviour be opt-in via config, given it's Claude-specific?
let's start without any claude session, In still need to figure the best way

55. Should the generated `.vscode/tasks.json` be a problem if the project *tracks* `.vscode/`? (In myapp it's gitignored — that won't be true everywhere. Merge into an existing tasks.json, or use a different mechanism?)
Let's leave this out for a moment as we won't start the claude session yet, and everything else (install etc) can be done in the script itself

## 7. Code standards

56. Bash, or POSIX sh? (Bash 3.2 ships with macOS; Bash 5 via brew. Do we require brew bash?)
No idea, whatever is default or most common on macos

57. Single file `bin/wtx`, or `bin/wtx` + sourced `lib/*.sh`? At what size do we split?
single file

58. `set -euo pipefail` in full, or keep `-uo` (the current scripts' choice, which tolerates the `[[ ... ]] && ...` idiom)?
whatever is best for standard CLI tools

59. Adopt `shellcheck` + `shfmt` as gates? Indent width, and `shfmt` flags?
yup

60. Tests: `bats-core`, or hand-rolled? Are tests worth it here at all, given every operation touches a real git repo and filesystem?
no tests for now, maybe later

61. If tests: do they create throwaway repos in `$TMPDIR`, and do we allow tests that actually open editor windows (probably not — so how do we fake `code`)?
n

62. Comment style: the current scripts carry a heavy "why" comment per step, which you liked. Keep that density in wtx?
No, lean comments only

63. Error message style — prefix with `wtx:`? Colour? Exit code discipline (0/1/2)?
Whatver is standard for the most used CLI tools

64. Dependency policy: is `jq` allowed? `gh`? Or must it be git + coreutils only?
Don't get the question

65. Any interest in rewriting in a real language later (Go/Rust for a single distributable binary), or is bash the permanent answer?
bash sounds enough for now

## 8. Repo & git standards

66. Commit convention: Conventional Commits (as myapp uses), or freeform?
conventional

67. Should this repo have husky/hooks, or is that overkill for a solo tool?
overkill

68. Branch workflow: commit straight to `main`, or PRs even solo?
straight to main

69. Do you want CI (GitHub Actions running shellcheck + bats), or is that ceremony?
not yet

70. License file? (Matters only if public.)
MIT

71. `CHANGELOG.md` — keep one by hand, or generate from commits, or skip?
skip

72. Should this repo carry its own `CLAUDE.md`/`AGENTS.md` for future sessions?
not yet

## 9. Distribution & release

73. Install method: `install.sh` symlinking `bin/wtx` into `~/.local/bin`? (I need to check whether that's on your PATH — see Part B.)
manual install in README telling to move to `~/.local/bin` or `~/bin` and add to PATH

74. Or `~/bin`? Or a Homebrew tap? Or `mise`?
...

75. Symlink (edits are live) or copy (stable, needs reinstall)? I lean symlink.
symlink only for dev

76. Versioning: SemVer tags, or just "whatever main is"?
no versioning for now

77. Does `wtx --version` read from a tag, a hardcoded constant, or git describe?
hardcoded alpha version

78. Do you want `wtx upgrade` (git pull in the tool repo)?
no

79. Shell completions for zsh — now, later, or never?
I have no idea how this works and what's standard

80. Any need for this to work over SSH / on a Linux box, or is macOS the only target?
should work on unix in general, must work on macOS 

## 10. Migration & out of scope

81. Once wtx exists, do we delete `scripts/wt.sh` and `scripts/wtrm.sh` from myapp, or leave thin wrappers?
I'll take care of that

82. Does the `.worktreeinclude` file stay in myapp (and get read by wtx), or move into a wtx config?
.worktreeinclude stays in each repo, it's like a gitignore for git, it's not part of the tool but consumed by the tool

83. Anything from the old hook-based flow you actually miss and want back?
no

84. Explicitly out of scope for v1 — my guess: bulk operations, PR integration, non-VSCode editors, non-macOS, Jira lookups. Confirm or correct?
I answered in the other questions

85. What's the smallest version of wtx that you'd start using daily? (This defines v1.)
no versioning, irrelevant question

## 11. Plan format

86. Plan style: the terse "sacrifice grammar for concision" style from your myapp CLAUDE.md, or prose?
SIMPLE ENGLISH, no grammar sacrifice, but concise, no buzzwords, etc

87. Should plan.md be a living document (updated as we build) or a snapshot we then ignore?
live

88. Do you want the plan to carry per-step checkboxes to tick off during implementation?
yes

89. Should each implementation step map to exactly one commit?
kinda, everything deliverable (single purpose change that doesn't break anything) should be a commit

90. Do you want the plan to end with an "unresolved questions" section (your CLAUDE.md convention)?
I don't get the relation to CLAUDE.md but yes for open questions and future ideas

91. Should the plan record *rejected* options and why (e.g. the node_modules copying we just rejected), or stay forward-looking only?
Yes

---

# Part B — Context established so far

## Origin

The user ran Claude Code sessions in git worktrees via a `WorktreeCreate` hook in
`~/dev/myapp`. Worktree **teardown** was never automatable that
way — Claude Code only removes worktrees it created itself (it marks them in git
metadata), so a hook-created worktree never becomes a removal candidate and
`WorktreeRemove` never fires. Teardown therefore lived in a manual script. With
teardown manual, the only remaining benefit of the hook was Claude's branch
isolation, which the user judged not worth the hook indirection.

**Decision: drop the hooks, use plain scripts.** Done, in that repo.

## What exists in myapp right now (the seed for wtx)

- `scripts/wt.sh` — create. Steps, in order: parse args → resolve main checkout
  via `--git-common-dir` → sanitize name to kebab-case → compute
  `<parent>/<repo>-<name>` + branch → guard dir *and* branch collisions → fetch
  + resolve `origin/main` → `git worktree add -b` → copy `.worktreeinclude`
  files → write `.vscode/tasks.json` → `code -n` → print path on stdout.
- `scripts/wtrm.sh` — remove. Sanitize the same way, locate the worktree, prompt
  on uncommitted changes, `worktree remove --force`, `worktree prune`, then
  delete the branch only if `merge-base --is-ancestor <branch> origin/main`
  (because `branch -d` compares against a usually-stale local `main`).
- `.worktreeinclude` — plain globs, one per line, of gitignored files to copy
  into a fresh worktree. Currently six `.env` files across `apps/*`.
- `.claude/hooks/` — **deleted**. The `hooks.WorktreeCreate` block was removed
  from `.claude/settings.local.json`.

Read those two scripts before writing the plan; they are the working reference
implementation and their comments explain each decision.

## Key mechanics already worked out

- **`--git-common-dir` to find the main checkout**, so the scripts work when run
  from inside another worktree (`.git/` is shared).
- **Name sanitizing** must be identical in create and remove, or they compute
  different paths. Currently: lowercase, non-alnum runs → single dash, trim.
- **Sibling directories**, so no editor window ever contains another worktree's
  files.
- **Base ref must be `origin/main`, not local `main`**, which is usually behind.
- **stdout = the path, stderr = everything else**, so `cd "$(wt.sh x)"` works.
- **Claude in the integrated terminal** requires a `runOn: folderOpen` VSCode
  task; that's the only hook point once `code -n` has been called. The task
  loads nvm explicitly (`. "$NVM_DIR/nvm.sh"; nvm use`) because a task shell may
  not apply `.nvmrc` and pnpm hard-fails on `engines.node`. It then runs
  `pnpm install` and `exec claude`.
- Under the old hook there was a session id, so the task ran `claude attach
  <id>`. A standalone script has no session id, so it starts a **fresh** session.
- `.vscode/` is gitignored in myapp, so the generated
  `tasks.json` doesn't dirty the worktree. **This will not be true in every
  repo** — see Q55.

## Rejected: copying node_modules instead of reinstalling

Investigated and dropped as not worth the risk. Findings, for the record:

- All pnpm symlinks are **relative** (`../../../node_modules/.pnpm/...`) and
  `virtualStoreDir: ".pnpm"`, so a symlink-preserving copy would land correctly
  in an identically-laid-out worktree.
- The disk is **APFS**, so `cp -Rc` would clone copy-on-write — 2.5G at ~no cost.
- **But** `node_modules/.bin/*` are generated shim scripts with the absolute repo
  path baked into `NODE_PATH`, so a copy silently points the worktree's binaries
  at the main checkout's tree.
- And caches like `apps/web/node_modules/.vite` are path-keyed.
- Both are fixed by running `pnpm install` afterwards — which is what the copy
  was trying to avoid. pnpm also already hardlinks from the global store at
  `~/Library/pnpm/store/v10`, so a cold install isn't a network install anyway.

## CLI conventions agreed as the target

- One executable, `case`-based subcommand dispatch (git/docker pattern). Single
  file until ~400 lines; git-style `libexec` dispatch judged overkill for three
  subcommands.
- `wtx <cmd>`, plus `help`/`--help`/`-h` all reaching one usage heredoc; usage on
  bare invocation; `--version`.
- Exit codes 0 / 1 / 2 (success / runtime failure / usage error).
- stdout is data, stderr is diagnostics.
- `NO_COLOR` honoured; colour only when `[[ -t 1 ]]`.
- Tooling: `shellcheck` (lint), `shfmt` (format), `bats-core` (tests).
- Install by **symlinking** into `~/.local/bin` (XDG), so a `git pull` in the
  tool repo updates the command. Homebrew tap only if it ever needs to reach
  other machines.
- Going global means removing the myapp assumptions: hardcoded
  `origin/main` (→ `git symbolic-ref refs/remotes/origin/HEAD`), `pnpm install`,
  `nvm use`, and `.worktreeinclude` at the repo root. **This is the real design
  work; the subcommand plumbing is trivial next to it.**

## Repo state

- `~/dev/XandruDavid/wtx`, git initialised on branch `main`.
- One commit, `68b211a chore: init wtx`, containing only `README.md`:
  "worktree-extended — a git worktree CLI: create, remove, and list worktrees as
  repo siblings, wired up for your editor."
- `plan.md` — skeleton with empty sections, to be filled from the answers above.
- Nothing else. No `bin/`, no tooling, no install script.

## Decisions still open

- The third subcommand (`list` is the placeholder assumption).
- Whether wtx lives in its own repo (chosen: yes, this one) vs. myapp.
- Everything in Part A.

## Environment facts

- macOS (Darwin 25.6.0), zsh, APFS.
- Editor: VSCode, launched with `code -n <dir>`; the user specifically needs
  Claude running in the **integrated** terminal, which is why the folderOpen task
  exists.
- myapp is a pnpm monorepo using nvm; not all target repos will be.
- `jq` is available (the old hook used it).
- `~/.local/bin` **exists but is NOT on `$PATH`** — installing there requires a
  `.zshrc` change. `~/bin` does not exist. (Q73/Q74 hinge on this.)
- `jq` is present at `/usr/bin/jq`. `shellcheck`, `shfmt` and `bats` are **not
  installed** — adopting them (Q59/Q60) means a `brew install` first.
