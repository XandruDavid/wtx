# wtx — Plan

> **For agentic workers:** implement this plan task by task with
> `superpowers:subagent-driven-development` or `superpowers:executing-plans`.
> Steps use `- [ ]` checkboxes. Tick them as you go — this file is live.
>
> **Questions and prior context:** [plan-writing-task.md](./plan-writing-task.md).
> Answers there are the source of truth for every decision below.

**Goal:** one bash command, `wtx`, that creates a git worktree as a repo
sibling, removes it, and lists the ones you have — so a Claude Code session can
run in isolation without touching your main checkout.

**How it works:** a single bash file, `bin/wtx`, with `case`-based subcommand
dispatch. Everything it needs it asks git for. It keeps no state about a repo
except one list of repos it has seen, used only by `wtx ls --all`.

**Built with:** bash 3.2, git 2.49, coreutils, `awk`, `column`. No `jq`, no `gh`,
no other language runtime.

## Global constraints

- Must run on **bash 3.2** — that is what ships with macOS. No `declare -A`, no
  `mapfile`, no `${var,,}`, no `**` globstar.
- Must work on macOS and other unix. No GNU-only flags: no `sed -i`, no
  `stat --format`, no `readlink -f`. In `awk`, no `length(array)` — that is a
  gawk extension and macOS `awk` does not have it.
- Every git behaviour below was verified on **git 2.49**. The newest thing used
  is `git worktree add --no-track`; if a teammate's git rejects it, that is the
  one flag to check.
- No config file. Flags, environment variables and defaults only.
- Never delete a branch. `wtx` creates branches; git deletes them.
- `shellcheck` and `shfmt` must pass before every commit.
- Conventional Commits, straight to `main`, no PRs, no hooks, no CI.

---

## 1. Intention

`wtx` exists to make one thing cheap: **start a fresh, isolated worktree for a
Claude Code task, or pick one up from a branch that already exists.**

It replaces the `WorktreeCreate` hook in Claude Code, which could not be made to
put worktrees outside the repo directory, and could never tear them down (Claude
Code only removes worktrees it created itself, so a hook-created worktree never
became a removal candidate and `WorktreeRemove` never fired).

Users: the author, teammates, maybe friends. Assumes macOS and VSCode for now.
Public repo, MIT, no distribution plan.

Speed matters, but correctness matters more. A `wtx new` that takes 30–60
seconds because it installs dependencies properly is better than one that takes
5 seconds and hands you a worktree that does not boot.

**What it deliberately is not:** a git workflow tool. It does not rebase, merge,
push, delete branches, or talk to GitHub.

## 2. Scope

### In scope

- `wtx new <name>` — worktree + branch + gitignored files + dependencies + editor.
- `wtx rm <name>` — worktree + directory gone, branch kept.
- `wtx ls` — what worktrees exist, grouped by repo.
- Resuming from a branch that already exists.
- `.worktreeinclude`: per-repo list of gitignored files and directories to copy in.

### Out of scope

- Deleting branches, checking PRs, rebasing, syncing (`wtx sync`).
- Editors other than VSCode. `$EDITOR`, Cursor, JetBrains, nvim: later.
- Starting a Claude session automatically. The right mechanism is still unclear,
  so `wtx new` just opens the editor.
- `wtx open`, `wtx cd`, `wtx prune`, `wtx doctor`, `wtx config`, `wtx exec`.
- Bulk removal, `--merged` sweeps, auto-generated worktree names.
- Jira ticket lookups.
- `git wtx <cmd>` as a git subcommand.
- Tests. Not now, maybe later.
- Windows. Bare repos. Submodule-heavy repos are untested.

## 3. Command surface

```
wtx new <name> [--branch <branch>] [--from <ref>] [--parent <dir>] [--resume]
wtx rm  <name|branch> [--force]
wtx ls  [--all]
wtx help | --help | -h
wtx --version
```

`rm`/`remove` and `ls`/`list` both work. `new` has no alias.

**Contract**

- stdout is data: `new` prints the worktree path and nothing else, so
  `cd "$(wtx new foo)"` works. `ls` prints its table.
- stderr is everything else: progress, warnings, errors, prompts.
- Exit 0 success, 1 runtime failure, 2 wrong usage.
- Errors are prefixed `wtx: `. Colour only when stderr is a terminal and
  `NO_COLOR` is unset.
- Bare `wtx` prints usage on stderr and exits 2.

### `wtx new <name>`

1. Parse flags.
2. Find the main checkout. Works from inside another worktree, because `.git` is
   shared and `--git-common-dir` always points at the main one.
3. Kebab-case the name: lowercase, runs of anything else become one dash, no
   leading or trailing dash. This is the **directory** name.
4. Branch name is the kebab-cased name, unless `--branch` says otherwise.
   `--branch` is passed through untouched and validated with
   `git check-ref-format --branch`, so `--branch feature/x` stays `feature/x`.
5. Parent directory is `../<repo>-worktrees` unless `$WTX_PARENT` or `--parent`
   overrides it. Create it if missing.
6. Refuse if the destination directory already exists.
7. **If the branch already exists:**
   - already checked out in a worktree → that worktree is the answer. Print its
     path, open the editor on it, exit 0.
   - not checked out anywhere → ask `resume from it? [y/N]`. `--resume` skips
     the question. With no terminal on stdin and no `--resume`, exit 1 and say
     to pass `--resume`. Then `git worktree add <dest> <branch>`.
8. **If the branch is new:** `git fetch --quiet origin`, resolve the base, then
   `git worktree add --no-track -b <branch> <dest> <base>`.
   - Base is `--from <ref>` if given. Otherwise the repo's **default branch**,
     tried in order: `origin/HEAD`, `origin/main`, local `main`, `HEAD`.
     `origin/HEAD` is a ref git sets at clone time recording what the remote
     itself calls its default branch, so it is right in a `master` or `develop`
     repo with nothing configured. If it ever goes stale,
     `git remote set-head origin -a` refreshes it.
     The local `main`/`HEAD` steps cover a repo with **no remote** — including
     this one today. There is no remote default to read there, so `wtx` branches
     off local `main`, and the new branch gets no upstream either, which is what
     a local-only repo wants.
   - Nothing resolves (a repo with no commits) → exit 1, pass `--from <ref>`.
   - Print which base was used, so a surprise is visible.
   - A failed fetch is a warning, not a failure — the refs already on disk do.
   - `--no-track` matters: without it git sets the new branch's upstream to the
     base, so a later `git push` aims at `main`. Branches start with **no
     upstream**, which is how you already work: the first `git push` fails with
     the `--set-upstream` command for you to copy.
9. Copy the files matched by `.worktreeinclude`.
10. Install dependencies, detected from the lockfile.
11. `code -n <dest>`. If `code` is missing, warn — do not fail.
12. Print the path on stdout.

### `wtx rm <name|branch>`

1. Find the main checkout.
2. Resolve the target from `git worktree list --porcelain`, matching either the
   branch name or the directory's basename, raw or kebab-cased.
   **Never recompute the path from the name.** Both worktrees in the author's
   `myapp` have a branch that no longer matches their directory,
   e.g. `...-fix-lint-naming` now holds branch
   `fix-lint-rules`. Branches get renamed; directories do not.
   Recomputation would miss them.
   - no match → exit 1, suggest `wtx ls`.
   - more than one match → exit 1, list them.
   - matched the main checkout → refuse.
3. Unless `--force`:
   - uncommitted changes → print `git status --short`, exit 1, say to pass
     `--force`.
   - commits on no remote → print `git log --oneline <branch> --not --remotes`,
     exit 1, say to push or pass `--force`. In a repo with no remote at all
     every commit would count as unpushed, so the check is skipped and says so
     — the uncommitted-changes gate above still applies.
   No interactive prompt here. You either pass `--force` or you do not.
4. `git worktree remove --force <dest>`, then `git worktree prune`. `--force` is
   safe at this point because the checks above already ran; it is there so git's
   own duplicate checks (untracked files, submodules) do not block us.
   If the directory is already gone, just prune.
5. Print `kept branch <branch>`. The branch is never touched.

### `wtx ls [--all]`

Grouped by repo. Group header is the repo name and its parent directory; paths
in the rows are relative to that parent, so rows stay narrow.

This is the real output of the §6 code against the author's repos, so it is
what you should see:

```
myapp (/Users/you/dev)
  BRANCH                            STATE  ±main    LAST COMMIT  PATH
  main (main checkout)              dirty  +0/-11   3 days ago   myapp
  fix-lint-rules  dirty  +0/-71   4 days ago   myapp-fix-lint-naming
  round-units    dirty  +11/-16  6 hours ago  myapp-tax-id

wtx (/Users/you/dev/XandruDavid)
  BRANCH                STATE  ±main  LAST COMMIT     PATH
  main (main checkout)  dirty  +0/-0  27 seconds ago  wtx
```

Note both worktree rows in the first group: the branch does not match the
directory name in either case, because the branches were renamed after the
worktrees were created. The second group has no remote, so its base comes from
the local `main` fallback.

- `STATE`: `clean`, `dirty`, or `gone` when the directory is missing.
- `±<default>`: `+ahead/-behind` against the repo's default branch, resolved the
  same way `new` resolves its base, so the header reads `±main`, `±master` or
  `±develop` to match. Never against the upstream: branches made by `wtx new`
  have none, so those counts would always be empty.
- `LAST COMMIT`: relative, from `git log -1 --format=%cr`.
- Alignment via `column -t -s $'\t'`, one pipe per group so each group aligns on
  its own. Rows carry no colour, because ANSI codes break `column`'s width
  arithmetic. Empty fields are written as `-`, because `column` collapses them.
  The `±` in the header is multi-byte; macOS `column` handles it, but if it
  misaligns for someone in a non-UTF-8 locale, rename the column to ASCII.
- No `--json`, no `--porcelain`.
- Plain `wtx ls` lists the current repo. `--all` lists every repo in the
  registry (see §4).

## 4. Configuration

No config file. Three inputs:

| Input | What it does | Default |
|---|---|---|
| `--parent <dir>` | where `new` puts this one worktree | `../<repo>-worktrees` |
| `$WTX_PARENT` | same, for every repo, set once in your shell rc | unset |
| `$NO_COLOR` | turn colour off | unset |

`.worktreeinclude` stays a plain file at each repo's root. It belongs to the
repo, not to `wtx` — like `.gitignore`, `wtx` only reads it. One glob per line,
`#` starts a comment, no gitignore syntax and no negations. A pattern matching
a directory copies it whole, with modes preserved, so a 600 key stays 600 and
symlinks stay symlinks. A trailing slash is optional: `certs/` and `certs` mean
the same thing.

**Registry.** `wtx ls --all` needs to know which repos exist, and git keeps no
global index of them. So `wtx new` and `wtx ls` append the main checkout's path
to `${XDG_STATE_HOME:-$HOME/.local/state}/wtx/repos`, deduplicated. `--all`
reads that file, drops paths that no longer exist, and runs `git worktree list`
in each. This is state, not config — you never edit it, and running `wtx ls`
once in a repo is enough to register it.

## 5. Repo layout & standards

```
bin/wtx        the whole tool
Makefile       lint, fmt
README.md      pitch, install, usage
LICENSE        MIT
plan.md        this file
.gitignore
```

One file. No `lib/`. Assembling the code in §6 gives a `bin/wtx` of about 530
lines including comments and blanks — that is fine for a single file, and the
`# --- section ---` banners keep it navigable. Only consider splitting if it
doubles.

**Shell rules** — all three confirmed against bash 3.2.57 on macOS:

- `set -euo pipefail`.
- Never end a function with `[[ ... ]] && action`. A failing test makes the
  function return 1, which under `-e` kills the caller. Use `if`.
  (`cond || die ...` is fine — the right side exits anyway.)
- Never `local x=$(cmd)` — that form swallows `cmd`'s failure. Write
  `local x; x=$(cmd)`.
- Never expand an empty array: `"${arr[@]}"` is an unbound-variable error in
  bash 3.2 under `set -u`. `${#arr[@]}` is safe, so guard on the count.
- Counters as `n=$((n + 1))`, not `((n++))`.
- Lean comments. Comment *why*, and only where the reason is not obvious. No
  step-by-step narration.
- `shellcheck bin/wtx` and `shfmt -i 2 -ci -d bin/wtx` must be clean. The one
  intentional `shellcheck disable` is the unquoted glob in the
  `.worktreeinclude` loop, which must stay unquoted to expand.

**Commits.** Conventional Commits. One commit per deliverable — a single change
that works on its own and breaks nothing. Straight to `main`.

## 6. Implementation steps

### How to check your work

There are no tests, so every task ends by running the thing. Make a throwaway
repo to run it against, so you never experiment on a real one:

```bash
scratch() {
  local d=${TMPDIR:-/tmp}/wtx-scratch
  rm -rf "$d" && mkdir -p "$d" && cd "$d"
  git init -q --bare remote.git
  git init -q repo && cd repo
  git config user.email t@t && git config user.name t
  echo hi >a.txt && git add . && git commit -qm init && git branch -M main
  # absolute, not ../remote.git: a relative remote URL is resolved against the
  # current worktree, so pushing from a worktree fails with
  # "fatal: '../remote.git' does not appear to be a git repository"
  git remote add origin "$d/remote.git" && git push -q -u origin main
  pwd
}
```

Each call wipes and rebuilds the fixture, so start a task's checks with
`cd "$(scratch)"` and you are in a clean repo at `.../wtx-scratch/repo`.

---

### Task 1: Tooling and licence

**Files:** create `Makefile`, `LICENSE`, `.gitignore`.

- [x] **Step 1: install the linters** — neither is on this machine yet.

```bash
brew install shellcheck shfmt
shellcheck --version && shfmt --version
```

- [x] **Step 2: write the `Makefile`** (tabs, not spaces, for the recipe lines)

```make
.PHONY: lint fmt check
lint:
	shellcheck bin/wtx
fmt:
	shfmt -i 2 -ci -w bin/wtx
check: lint
	shfmt -i 2 -ci -d bin/wtx
```

- [x] **Step 3: write `LICENSE`** — the MIT text, `Copyright (c) 2026 Alexandru David`.

- [x] **Step 4: write `.gitignore`**

```
.DS_Store
```

- [x] **Step 5: commit**

```bash
git add Makefile LICENSE .gitignore
git commit -m "chore: add MIT licence and lint/format targets"
```

---

### Task 2: The skeleton — dispatch, help, version

**Files:** create `bin/wtx`; modify `README.md`.

**Produces:** `die`, `warn`, `info`, `usage_err`, `usage`, `main`. Later tasks
add `cmd_new`, `cmd_rm`, `cmd_ls` and call these.

- [x] **Step 1: write `bin/wtx`**

```bash
#!/usr/bin/env bash
# wtx - git worktrees as repo siblings. See README.md.
set -euo pipefail

WTX_VERSION="0.0.0-alpha"

# --- output ----------------------------------------------------------------
# All messages go to stderr; stdout is reserved for paths and tables.

if [[ -t 2 && -z ${NO_COLOR-} ]]; then
  C_RED=$'\033[31m'
  C_YEL=$'\033[33m'
  C_OFF=$'\033[0m'
else
  C_RED='' C_YEL='' C_OFF=''
fi

info() { printf '%s\n' "$*" >&2; }
warn() { printf '%swtx: %s%s\n' "$C_YEL" "$*" "$C_OFF" >&2; }

die() {
  printf '%swtx: %s%s\n' "$C_RED" "$*" "$C_OFF" >&2
  exit 1
}

usage_err() {
  printf '%swtx: %s%s\n' "$C_RED" "$*" "$C_OFF" >&2
  printf "run 'wtx help' for usage\n" >&2
  exit 2
}

usage() {
  cat <<'EOF'
wtx - git worktrees as repo siblings

usage:
  wtx new <name> [--branch <branch>] [--from <ref>] [--parent <dir>] [--resume]
  wtx rm  <name|branch> [--force]
  wtx ls  [--all]
  wtx help
  wtx --version

new   create <parent>/<name> with a new branch off the default branch, copy the
      files listed in .worktreeinclude, install dependencies, open VSCode.
      if the branch already exists, offer to resume from it.
rm    remove a worktree and its directory. never deletes the branch.
ls    list worktrees grouped by repo. --all covers every repo wtx has seen.

  --branch <branch>  branch name, if it should differ from the directory name
  --from <ref>       what to branch off, instead of the default branch
  --parent <dir>     where to put the worktree
  --resume           check out an existing branch without asking
  --force            remove even with uncommitted or unpushed work
  --all              every repo, not just this one

parent directory defaults to ../<repo>-worktrees; set WTX_PARENT to change it.
stdout is data, stderr is messages. exit 0 ok, 1 failed, 2 bad usage.
EOF
}

# --- dispatch --------------------------------------------------------------

main() {
  local cmd=${1-}
  if [[ $# -gt 0 ]]; then shift; fi

  case $cmd in
    new) cmd_new "$@" ;;
    rm | remove) cmd_rm "$@" ;;
    ls | list) cmd_ls "$@" ;;
    help | --help | -h) usage ;;
    --version) printf 'wtx %s\n' "$WTX_VERSION" ;;
    '')
      usage >&2
      exit 2
      ;;
    *) usage_err "unknown command: $cmd" ;;
  esac
}

main "$@"
```

- [x] **Step 2: add three stubs** so dispatch works before the real ones land.
  Delete each stub in the task that implements it.

```bash
cmd_new() { die "not implemented"; }
cmd_rm() { die "not implemented"; }
cmd_ls() { die "not implemented"; }
```

- [x] **Step 3: make it executable and check it**

```bash
chmod +x bin/wtx
./bin/wtx --version          # -> wtx 0.0.0-alpha
./bin/wtx help | head -3     # -> the usage block
./bin/wtx; echo "exit=$?"    # -> usage on stderr, exit=2
./bin/wtx bogus; echo "exit=$?"  # -> wtx: unknown command: bogus, exit=2
make check                   # -> clean
```

- [x] **Step 4: write `README.md`** — pitch, install, usage. Install must say
  that `~/.local/bin` exists on this machine but is **not** on `$PATH`.

```markdown
# wtx

worktree-extended — git worktrees as repo siblings, ready to work in.

`wtx new fix-the-thing` gives you a fresh worktree next to your repo, on a new
branch off your repo's default branch, with your gitignored `.env` files copied in,
dependencies installed, and a VSCode window open on it. `wtx rm fix-the-thing`
takes the worktree away and leaves the branch alone. `wtx ls` shows you what
you have.

Requires bash, git and macOS or another unix. VSCode is assumed.

## Install

Symlink it, so `git pull` in this repo updates the command:

    ln -s "$PWD/bin/wtx" ~/.local/bin/wtx

`~/.local/bin` must be on your `$PATH`. If it is not, add this to `~/.zshrc`:

    export PATH="$HOME/.local/bin:$PATH"

`~/bin` works just as well if you prefer it.

## Usage

    wtx new <name>      create a worktree and open it
    wtx rm  <name>      remove a worktree, keep the branch
    wtx ls              list worktrees, grouped by repo

`wtx help` has the flags.

## .worktreeinclude

A worktree is a fresh checkout, so gitignored files are missing and most
projects do not boot. List them at your repo root in `.worktreeinclude`, one
glob per line, and `wtx new` copies them in:

    # gitignored files every worktree needs
    apps/web/.env
    apps/api/.env
    certs/

Directories are copied whole and file modes are preserved, so a local TLS key
keeps its permissions. Point a glob at something huge and `wtx new` gets slow —
that is on the pattern, not the tool.

The file belongs to your repo, not to wtx. Commit it or gitignore it, your call.

## Development

    make fmt      # shfmt
    make check    # shellcheck + shfmt --diff
```

- [x] **Step 5: commit**

```bash
git add bin/wtx README.md
git commit -m "feat: add wtx skeleton with subcommand dispatch"
```

---

### Task 3: Git helpers and `wtx ls` for the current repo

**Files:** modify `bin/wtx`.

**Produces:** `require_repo`, `main_checkout`, `sanitize_name`,
`worktree_parent`, `default_base`, `list_worktrees`, `ahead_behind`,
`print_repo_group`, `cmd_ls`. Tasks 4–9 all use these.

`list_worktrees` is the important one: every later decision reads git's own
worktree list rather than rebuilding a path from a name.

- [x] **Step 1: add the git helpers** above the dispatch section

```bash
# --- git -------------------------------------------------------------------

require_repo() {
  git rev-parse --git-common-dir >/dev/null 2>&1 ||
    die "not a git repository: $PWD"
  if [[ $(git rev-parse --is-bare-repository) == true ]]; then
    die "bare repositories are not supported"
  fi
}

# The main checkout, even when called from inside another worktree: .git is
# shared, so --git-common-dir always points at the main one.
main_checkout() {
  dirname "$(git rev-parse --path-format=absolute --git-common-dir)"
}

# The name becomes a directory, so kebab-case it.
sanitize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

worktree_parent() {
  if [[ -n ${WTX_PARENT-} ]]; then
    printf '%s\n' "$WTX_PARENT"
    return 0
  fi
  printf '%s/%s-worktrees\n' "$(dirname "$1")" "$(basename "$1")"
}

# The branch to start new work from, as a ref.
#   origin/HEAD  - set at clone time, records what the remote calls its default
#                  branch, so this is right in a master or develop repo
#   origin/main  - for clones old enough to be missing origin/HEAD
#   main / HEAD  - no remote at all, so there is no remote default to read
# Empty only in a repo with no commits; callers decide whether that is fatal.
default_base() {
  local head
  head=$(git -C "$1" symbolic-ref --quiet refs/remotes/origin/HEAD) || head=''
  if [[ -n $head ]]; then
    printf '%s\n' "${head#refs/remotes/}"
    return 0
  fi
  local ref
  for ref in origin/main main HEAD; do
    if git -C "$1" rev-parse --verify --quiet "$ref" >/dev/null; then
      printf '%s\n' "$ref"
      return 0
    fi
  done
}

# One TAB-separated line per worktree: path, branch ("-" if detached), state.
list_worktrees() {
  git -C "$1" worktree list --porcelain | awk '
    function flush() { if (p != "") print p "\t" (b == "" ? "-" : b) "\t" s }
    /^worktree /   { flush(); p = substr($0, 10); b = ""; s = "ok" }
    /^branch /     { b = substr($0, 8); sub(/^refs\/heads\//, "", b) }
    /^detached$/   { b = "" }
    /^prunable /   { s = "gone" }
    /^locked/      { s = "locked" }
    END            { flush() }
  '
}
```

- [x] **Step 2: add `cmd_ls`** (replacing the stub)

```bash
# --- ls --------------------------------------------------------------------

# "+ahead/-behind" against the default branch. Not against the upstream:
# branches made by `wtx new` have none, so those counts would always be empty.
ahead_behind() {
  local repo=$1 branch=$2 base=$3
  if [[ $branch == '-' || -z $base ]]; then
    printf '%s\n' -
    return 0
  fi
  local counts
  counts=$(git -C "$repo" rev-list --left-right --count "$base...$branch" 2>/dev/null) ||
    { printf '%s\n' -; return 0; }
  printf '+%s/-%s\n' "$(printf '%s' "$counts" | cut -f2)" \
    "$(printf '%s' "$counts" | cut -f1)"
}

# One group: a header, then the rows aligned on their own. Piping each group
# separately keeps a wide path in one repo from padding another.
print_repo_group() {
  local repo=$1
  local parent base base_label
  parent=$(dirname "$repo")
  base=$(default_base "$repo")
  base_label=${base##*/}   # origin/main -> main
  if [[ -z $base_label ]]; then base_label=base; fi
  printf '\n%s (%s)\n' "$(basename "$repo")" "$parent"

  {
    # header names what it compares against: ±main, ±master, ±develop
    printf 'BRANCH\tSTATE\t±%s\tLAST COMMIT\tPATH\n' "$base_label"
    local path branch state label dirty when
    while IFS=$'\t' read -r path branch state; do
      label=$branch
      if [[ $path == "$repo" ]]; then label="$branch (main checkout)"; fi

      if [[ ! -d $path ]]; then
        dirty=gone
        when='-'
      else
        dirty=clean
        if [[ -n $(git -C "$path" status --porcelain) ]]; then dirty=dirty; fi
        when=$(git -C "$path" log -1 --format=%cr 2>/dev/null || printf '%s' -)
      fi
      if [[ $state == locked ]]; then dirty="$dirty,locked"; fi

      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$label" "$dirty" "$(ahead_behind "$repo" "$branch" "$base")" \
        "$when" "${path#"$parent"/}"
    done < <(list_worktrees "$repo")
  } | column -t -s $'\t' | sed 's/^/  /'
}

cmd_ls() {
  local all=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --all | -a) all=1 ;;
      *) usage_err "unknown argument: $1" ;;
    esac
    shift
  done

  if [[ $all -eq 1 ]]; then
    die "--all is not implemented yet"
  fi

  require_repo
  local repo
  repo=$(main_checkout)
  print_repo_group "$repo"
}
```

- [x] **Step 3: check it against a repo that already has worktrees**

```bash
cd ~/dev/myapp && ~/dev/XandruDavid/wtx/bin/wtx ls
```

Expect one group header plus a row per worktree, with `±main` as the third
column header. Two rows will show a branch that does not match its directory
name (e.g. branch `fix-lint-rules` under a directory named
`...-fix-lint-naming`) — that mismatch is the whole reason
`list_worktrees` exists instead of path arithmetic. Then:

```bash
cd /tmp && ~/dev/XandruDavid/wtx/bin/wtx ls; echo "exit=$?"
# -> wtx: not a git repository: /tmp, exit=1
NO_COLOR=1 ~/dev/XandruDavid/wtx/bin/wtx ls 2>&1 | cat -v | grep -c '\^\[' || echo "no ANSI, good"

# a repo with no remote: falls back to local main, so still ±main
cd ~/dev/XandruDavid/wtx && ~/dev/XandruDavid/wtx/bin/wtx ls
make check
```

- [x] **Step 4: commit**

```bash
git add bin/wtx
git commit -m "feat: add wtx ls for the current repo"
```

---

### Task 4: `wtx new` — the core

**Files:** modify `bin/wtx`.

**Consumes:** `require_repo`, `main_checkout`, `sanitize_name`,
`worktree_parent`, `default_base`, `list_worktrees` from Task 3.

**Produces:** `cmd_new`, `open_editor`, `create_branch_worktree`. Tasks 5–7 add
calls inside `cmd_new`.

- [x] **Step 1: add `open_editor` and `create_branch_worktree`**

```bash
# --- new -------------------------------------------------------------------

open_editor() {
  if ! command -v code >/dev/null; then
    warn "code is not on PATH, no window opened"
    return 0
  fi
  code -n "$1" >&2 || warn "could not open a VSCode window for $1"
}

create_branch_worktree() {
  local repo=$1 branch=$2 dest=$3 from=$4

  if git -C "$repo" remote | grep -qx origin; then
    git -C "$repo" fetch --quiet origin ||
      warn "fetch failed, using the origin refs already on disk"
  fi

  # Resolve after the fetch, so origin/HEAD is as fresh as it can be.
  local base=$from
  if [[ -z $base ]]; then base=$(default_base "$repo"); fi
  if [[ -z $base ]]; then
    die "nothing to branch from here; pass --from <ref>"
  fi
  if ! git -C "$repo" rev-parse --verify --quiet "$base" >/dev/null; then
    die "cannot resolve $base"
  fi
  info "branching off $base"

  # --no-track, or git makes the base the new branch's upstream and a later
  # `git push` aims at main. No upstream is deliberate: your first push fails
  # with the `--set-upstream` command to copy, which is how you already work.
  git -C "$repo" worktree add --no-track -b "$branch" "$dest" "$base" >&2 ||
    die "git worktree add failed for $dest"
}
```

- [x] **Step 2: add `cmd_new`** (replacing the stub). The resume branch calls a
  function that Task 7 writes; until then it dies with a clear message.

```bash
# shellcheck disable=SC2034  # resume is consumed by resume_branch, added next
cmd_new() {
  local name='' branch='' from='' parent='' resume=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --branch)
        branch=${2-}
        if [[ -z $branch ]]; then usage_err "--branch needs a value"; fi
        shift
        ;;
      --from)
        from=${2-}
        if [[ -z $from ]]; then usage_err "--from needs a value"; fi
        shift
        ;;
      --parent)
        parent=${2-}
        if [[ -z $parent ]]; then usage_err "--parent needs a value"; fi
        shift
        ;;
      --resume) resume=1 ;;
      -*) usage_err "unknown flag: $1" ;;
      *)
        if [[ -n $name ]]; then usage_err "new takes one name"; fi
        name=$1
        ;;
    esac
    shift
  done
  if [[ -z $name ]]; then usage_err "new needs a name"; fi

  require_repo
  local repo
  repo=$(main_checkout)

  name=$(sanitize_name "$name")
  if [[ -z $name ]]; then die "that name has no usable characters in it"; fi
  if [[ -z $branch ]]; then branch=$name; fi
  git check-ref-format --branch "$branch" >/dev/null 2>&1 ||
    die "not a valid branch name: $branch"

  if [[ -z $parent ]]; then parent=$(worktree_parent "$repo"); fi
  local dest="$parent/$name"
  if [[ -e $dest ]]; then die "already exists: $dest"; fi
  mkdir -p "$parent"

  if git -C "$repo" show-ref --quiet --verify "refs/heads/$branch"; then
    die "branch $branch already exists (resume is not implemented yet)"
  else
    create_branch_worktree "$repo" "$branch" "$dest" "$from"
  fi

  open_editor "$dest"
  info "worktree ready at $dest on branch $branch"
  printf '%s\n' "$dest"
}
```

- [x] **Step 3: check it in a throwaway repo**

```bash
# use the scratch() helper from the top of section 6
cd "$(scratch)"           # you are now in .../wtx-scratch/repo
W=~/dev/XandruDavid/wtx/bin/wtx

"$W" new "Fix The Thing"        # name gets kebab-cased
# -> prints .../wtx-scratch/repo-worktrees/fix-the-thing on stdout
ls -d ../repo-worktrees/fix-the-thing
git -C ../repo-worktrees/fix-the-thing branch --show-current   # -> fix-the-thing
git config --get branch.fix-the-thing.remote || echo "no upstream, correct"

"$W" new other --branch feature/keep-my-slashes
git -C ../repo-worktrees/other branch --show-current           # -> feature/keep-my-slashes

"$W" new fix-the-thing; echo "exit=$?"    # -> already exists, exit=1
WTX_PARENT="$PWD/../elsewhere" "$W" new somewhere && ls -d ../elsewhere/somewhere
make -C ~/dev/XandruDavid/wtx check
```

Then the case `origin/HEAD` is there for — a `master` repo that also has a
decoy `main` branch. `wtx new` must branch off `master`:

```bash
d=${TMPDIR:-/tmp}/wtx-master && rm -rf "$d" && mkdir -p "$d" && cd "$d"
git init -q --bare remote.git
git init -q -b master src && cd src
git config user.email t@t && git config user.name t
echo a >a && git add . && git commit -qm "real work on master"
git remote add origin "$d/remote.git" && git push -q origin master
git checkout -q -b main && echo stale >stale && git add . &&
  git commit -qm "abandoned main" && git push -q origin main
git -C "$d/remote.git" symbolic-ref HEAD refs/heads/master
cd "$d" && git clone -q remote.git clone && cd clone

"$W" new from-default
# -> "branching off origin/master"
git -C ../clone-worktrees/from-default log -1 --format=%s
# -> "real work on master", NOT "abandoned main"
```

- [x] **Step 4: commit**

```bash
git add bin/wtx
git commit -m "feat: add wtx new for fresh branches"
```

---

### Task 5: Copy the files and directories from `.worktreeinclude`

**Files:** modify `bin/wtx`.

**Consumes:** `info` from Task 2.
**Produces:** `copy_includes`, called from `cmd_new`.

- [x] **Step 1: add `copy_includes`**

```bash
# A worktree is a fresh checkout, so gitignored files like .env are missing and
# most projects do not boot. Plain globs, one per line, not gitignore syntax:
# no negations. A pattern matching a directory copies it whole, so a careless
# glob can make `wtx new` slow - that is on whoever wrote the pattern.
copy_includes() {
  local repo=$1 dest=$2
  local file="$repo/.worktreeinclude"
  if [[ ! -f $file ]]; then return 0; fi

  local files=0 dirs=0 pattern src rel
  while IFS= read -r pattern || [[ -n $pattern ]]; do
    pattern=${pattern%%#*}
    pattern=$(printf '%s' "$pattern" | tr -d '[:space:]')
    pattern=${pattern%/}   # "certs/" and "certs" mean the same thing
    if [[ -z $pattern ]]; then continue; fi
    # shellcheck disable=SC2086  # unquoted on purpose: the glob must expand
    for src in "$repo"/$pattern; do
      if [[ ! -e $src ]]; then continue; fi
      rel=${src#"$repo"/}
      mkdir -p "$dest/$(dirname "$rel")"
      # -R so a directory comes whole, -p to keep modes and times - a 600 key
      # must stay 600. cp keeps symlinks as symlinks rather than following them.
      cp -Rp "$src" "$dest/$rel"
      if [[ -d $src ]]; then dirs=$((dirs + 1)); else files=$((files + 1)); fi
    done
  done <"$file"

  if [[ $dirs -gt 0 ]]; then
    info "copied $files file(s) and $dirs directory(ies) from .worktreeinclude"
  elif [[ $files -gt 0 ]]; then
    info "copied $files file(s) from .worktreeinclude"
  fi
}
```

- [x] **Step 2: call it in `cmd_new`**, right after the worktree exists and
  before `open_editor`:

```bash
  copy_includes "$repo" "$dest"
```

- [x] **Step 3: check it**

```bash
cd "$(scratch)"
mkdir -p apps/web certs
printf 'SECRET=1\n' >apps/web/.env
printf 'IGNORED=1\n' >.env.local
printf 'cert\n' >certs/dev.pem && chmod 600 certs/dev.pem
printf '.env*\napps/*/.env\ncerts/\n' >.gitignore
printf '# needed by every worktree\napps/*/.env\n.env.local\ncerts/\n' >.worktreeinclude
git add -A && git commit -qm "add worktreeinclude"

~/dev/XandruDavid/wtx/bin/wtx new inc-test
# -> "copied 2 file(s) and 1 directory(ies) from .worktreeinclude"
cat ../repo-worktrees/inc-test/apps/web/.env   # -> SECRET=1
cat ../repo-worktrees/inc-test/.env.local               # -> IGNORED=1
cat ../repo-worktrees/inc-test/certs/dev.pem            # -> cert

# a private key must not become world-readable in the copy
ls -l ../repo-worktrees/inc-test/certs/dev.pem          # -> -rw-------

# a pattern matching nothing must not break anything
printf 'does/not/exist/*\n' >>.worktreeinclude
~/dev/XandruDavid/wtx/bin/wtx new inc-test-2   # -> still succeeds
make -C ~/dev/XandruDavid/wtx check            # the SC2086 disable must be there
```

- [x] **Step 4: commit**

```bash
git add bin/wtx
git commit -m "feat: copy .worktreeinclude files into new worktrees"
```

---

### Task 6: Install dependencies

**Files:** modify `bin/wtx`.

**Consumes:** `info`, `warn`.
**Produces:** `run_setup`, called from `cmd_new`.

This runs in `wtx`'s own process, which inherits your shell's environment — so
nvm's node is already on `$PATH` and no `nvm use` dance is needed. That is the
reason this is not a VSCode task like the old script used.

- [x] **Step 1: add `run_setup`**

```bash
# Install before the editor opens, so the window is ready when it appears.
# Detected from the lockfile; first match wins.
run_setup() {
  local dest=$1
  local -a install_cmd=()

  if [[ -f $dest/pnpm-lock.yaml ]]; then
    install_cmd=(pnpm install)
  elif [[ -f $dest/bun.lock || -f $dest/bun.lockb ]]; then
    install_cmd=(bun install)
  elif [[ -f $dest/yarn.lock ]]; then
    install_cmd=(yarn install)
  elif [[ -f $dest/package-lock.json ]]; then
    install_cmd=(npm install)
  elif [[ -f $dest/uv.lock ]]; then
    install_cmd=(uv sync)
  elif [[ -f $dest/Cargo.lock ]]; then
    install_cmd=(cargo fetch)
  fi

  if [[ ${#install_cmd[@]} -eq 0 ]]; then
    # Say so: an undetected repo should not look like a silent no-op.
    info "no lockfile found, skipping dependency install"
    return 0
  fi
  if ! command -v "${install_cmd[0]}" >/dev/null; then
    warn "${install_cmd[0]} is not on PATH, skipping ${install_cmd[*]}"
    return 0
  fi

  info "running ${install_cmd[*]}"
  # A failed install still leaves a usable worktree, so warn and carry on.
  (cd "$dest" && "${install_cmd[@]}") >&2 ||
    warn "${install_cmd[*]} failed; run it yourself in $dest"
}
```

Note the empty-array rule from §5: the guard is on `${#cmd[@]}`, and
`"${cmd[@]}"` is only expanded after that guard passes.

- [x] **Step 2: call it in `cmd_new`**, after `copy_includes` and before
  `open_editor`:

```bash
  run_setup "$dest"
```

- [x] **Step 3: check it**

```bash
cd "$(scratch)"
printf '{"name":"t","private":true}\n' >package.json
printf 'lockfileVersion: "9.0"\n' >pnpm-lock.yaml
git add -A && git commit -qm "add pnpm lockfile"
~/dev/XandruDavid/wtx/bin/wtx new setup-test   # -> "running pnpm install"

# no lockfile at all: says so, does not fail
cd "$(scratch)" && ~/dev/XandruDavid/wtx/bin/wtx new no-lockfile
# -> "no lockfile found, skipping dependency install"
make -C ~/dev/XandruDavid/wtx check
```

Then the real one — this is the case the 30–60 second budget was set for:

```bash
cd ~/dev/myapp
time ~/dev/XandruDavid/wtx/bin/wtx new wtx-smoke-test
# expect pnpm install to hardlink from the store, well under a minute
```

- [x] **Step 4: commit**

```bash
git add bin/wtx
git commit -m "feat: install dependencies in new worktrees"
```

---

### Task 7: `wtx new` on a branch that already exists

**Files:** modify `bin/wtx`.

**Consumes:** `list_worktrees`, `open_editor`.
**Produces:** `resume_branch`, replacing the `die` in `cmd_new`.

Two cases. Already checked out somewhere → that worktree is the answer, no
question needed. Not checked out → ask, because a name collision is more often
a typo than an intention.

- [ ] **Step 1: add `resume_branch`**

```bash
resume_branch() {
  local repo=$1 branch=$2 dest=$3 resume=$4

  local existing
  existing=$(list_worktrees "$repo" |
    awk -F'\t' -v b="$branch" '$2 == b { print $1; exit }')

  if [[ -n $existing ]]; then
    info "branch $branch is already checked out at $existing"
    open_editor "$existing"
    printf '%s\n' "$existing"
    exit 0
  fi

  if [[ $resume -eq 0 ]]; then
    if [[ ! -t 0 ]]; then
      die "branch $branch already exists; pass --resume to check it out into $dest"
    fi
    info "branch $branch already exists and is not checked out anywhere"
    local reply
    read -rp "resume from it in $dest? [y/N] " reply
    case $reply in
      [yY] | [yY][eE][sS]) ;;
      *) die "aborted" ;;
    esac
  fi

  git -C "$repo" worktree add "$dest" "$branch" >&2 ||
    die "git worktree add failed for $dest"
}
```

- [ ] **Step 2: replace the placeholder in `cmd_new`**

`resume` is now actually read, so delete the
`# shellcheck disable=SC2034` line directly above `cmd_new() {` — it was only
there to keep Task 4 lint-clean.

Change:

```bash
    die "branch $branch already exists (resume is not implemented yet)"
```

to:

```bash
    resume_branch "$repo" "$branch" "$dest" "$resume"
```

- [ ] **Step 3: check all three paths**

```bash
cd "$(scratch)"
W=~/dev/XandruDavid/wtx/bin/wtx

# a) branch exists, not checked out -> asks, --resume skips the question
git branch parked origin/main
"$W" new parked --resume
git -C ../repo-worktrees/parked branch --show-current   # -> parked

# b) branch exists AND is checked out -> prints the existing path, exit 0
"$W" new parked-again --branch parked
# -> "already checked out at .../repo-worktrees/parked", stdout is that path

# c) no terminal on stdin and no --resume -> refuses
git branch other-parked origin/main
"$W" new other-parked </dev/null; echo "exit=$?"
# -> "pass --resume", exit=1

# d) the interactive prompt: answer n
"$W" new other-parked      # type n -> "wtx: aborted"
make -C ~/dev/XandruDavid/wtx check
```

- [ ] **Step 4: commit**

```bash
git add bin/wtx
git commit -m "feat: resume wtx new from an existing branch"
```

---

### Task 8: `wtx rm`

**Files:** modify `bin/wtx`.

**Consumes:** `require_repo`, `main_checkout`, `sanitize_name`, `list_worktrees`.
**Produces:** `find_worktree`, `cmd_rm`.

- [ ] **Step 1: add `find_worktree`**

```bash
# --- rm --------------------------------------------------------------------

# Match by branch name or by directory basename, raw or kebab-cased. Never
# rebuild the path from the name: a worktree's directory and its branch can
# differ, and --parent means the path is not predictable anyway.
find_worktree() {
  local repo=$1 raw=$2 sane=$3
  list_worktrees "$repo" | awk -F'\t' -v raw="$raw" -v sane="$sane" -v r="$repo" '
    $1 == r { next }
    $2 == raw || $2 == sane { print; next }
    { k = split($1, a, "/"); if (a[k] == raw || a[k] == sane) print }
  '
}
```

`k = split(...)` then `a[k]` on purpose — `length(array)` is a gawk extension
and macOS awk does not have it.

- [ ] **Step 2: add `cmd_rm`** (replacing the stub)

```bash
cmd_rm() {
  local force=0 needle=''
  while [[ $# -gt 0 ]]; do
    case $1 in
      --force | -f) force=1 ;;
      -*) usage_err "unknown flag: $1" ;;
      *)
        if [[ -n $needle ]]; then usage_err "rm takes one name"; fi
        needle=$1
        ;;
    esac
    shift
  done
  if [[ -z $needle ]]; then usage_err "rm needs a worktree name"; fi

  require_repo
  local repo
  repo=$(main_checkout)

  local matches count
  matches=$(find_worktree "$repo" "$needle" "$(sanitize_name "$needle")")
  count=$(printf '%s' "$matches" | grep -c . || true)

  if [[ $count -eq 0 ]]; then
    die "no worktree matching '$needle' - try: wtx ls"
  fi
  if [[ $count -gt 1 ]]; then
    info "'$needle' matches more than one worktree:"
    printf '%s\n' "$matches" | cut -f1 >&2
    die "name one of them exactly"
  fi

  local dest branch state
  IFS=$'\t' read -r dest branch state <<<"$matches"

  if [[ $force -eq 0 ]]; then
    if [[ -d $dest ]] && [[ -n $(git -C "$dest" status --porcelain) ]]; then
      info "$dest has uncommitted changes:"
      git -C "$dest" status --short >&2
      die "commit or stash them, or pass --force"
    fi
    # Only that it is on *a* remote. Whether it is merged is git's business.
    if [[ $branch != '-' ]]; then
      if [[ -z $(git -C "$repo" remote) ]]; then
        # Every commit would count as unpushed, so the check says nothing here.
        # Say that out loud rather than silently dropping a safety net.
        info "this repo has no remote, so there is nothing to check against"
      else
        local unpushed
        unpushed=$(git -C "$repo" rev-list --count "$branch" --not --remotes)
        if [[ $unpushed -gt 0 ]]; then
          info "$branch has $unpushed commit(s) that are on no remote:"
          git -C "$repo" log --oneline "$branch" --not --remotes >&2
          die "push them, or pass --force"
        fi
      fi
    fi
  fi

  if [[ -d $dest ]]; then
    # --force is safe here: the checks above already ran, and this stops git's
    # own duplicate checks (untracked files, submodules) from blocking us.
    git -C "$repo" worktree remove --force "$dest" || die "could not remove $dest"
  fi
  git -C "$repo" worktree prune
  info "removed worktree $dest"
  if [[ $branch != '-' ]]; then info "kept branch $branch"; fi
  if [[ $state == locked ]]; then warn "that worktree was locked"; fi
}
```

- [ ] **Step 3: check every gate**

```bash
cd "$(scratch)"
W=~/dev/XandruDavid/wtx/bin/wtx

# clean and pushed -> removes, keeps the branch
"$W" new gone-soon
git -C ../repo-worktrees/gone-soon push -q -u origin gone-soon
"$W" rm gone-soon
git branch --list gone-soon    # -> still there
ls -d ../repo-worktrees/gone-soon 2>&1   # -> No such file

# unpushed commits -> refuses
"$W" new unpushed
git -C ../repo-worktrees/unpushed commit -q --allow-empty -m wip
"$W" rm unpushed; echo "exit=$?"         # -> "push them, or pass --force", exit=1
"$W" rm unpushed --force                 # -> removed

# uncommitted changes -> refuses
"$W" new dirty && echo x >../repo-worktrees/dirty/new.txt
"$W" rm dirty; echo "exit=$?"            # -> "commit or stash them", exit=1
"$W" rm dirty --force                    # -> removed

# resolves by branch when the directory name differs
"$W" new dirname --branch feature/other-name
git -C ../repo-worktrees/dirname push -q -u origin feature/other-name
"$W" rm feature/other-name               # -> found and removed
"$W" new dirname2 --branch feature/x
git -C ../repo-worktrees/dirname2 push -q -u origin feature/x
"$W" rm dirname2                         # -> found by directory name too

# refuses the main checkout, and unknown names
"$W" rm main; echo "exit=$?"             # -> no worktree matching 'main', exit=1
"$W" rm nope; echo "exit=$?"             # -> exit=1

# a directory deleted by hand -> prunes cleanly
"$W" new manual && rm -rf ../repo-worktrees/manual
"$W" rm manual                           # -> removed, no git error
make -C ~/dev/XandruDavid/wtx check
```

- [ ] **Step 4: commit**

```bash
git add bin/wtx
git commit -m "feat: add wtx rm, keeping the branch"
```

---

### Task 9: The registry and `wtx ls --all`

**Files:** modify `bin/wtx`; modify `README.md`.

**Consumes:** `main_checkout`, `print_repo_group`.
**Produces:** `registry_file`, `register_repo`, `registered_repos`; `--all` in
`cmd_ls`.

git keeps no global index of worktrees, so `--all` needs one. `wtx new` and
`wtx ls` write the main checkout's path to a state file; `--all` reads it and
asks git the rest.

- [ ] **Step 1: add the registry functions**

```bash
# --- registry --------------------------------------------------------------
# git has no global list of repos, so `ls --all` needs one. new and ls append
# to it, so a repo registers itself the first time you use wtx in it.

registry_file() {
  printf '%s/wtx/repos\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

register_repo() {
  local file
  file=$(registry_file)
  mkdir -p "$(dirname "$file")"
  if [[ -f $file ]] && grep -qxF "$1" "$file"; then return 0; fi
  printf '%s\n' "$1" >>"$file"
}

# Registered repos that still exist, most recently registered last.
registered_repos() {
  local file repo
  file=$(registry_file)
  if [[ ! -f $file ]]; then return 0; fi
  while IFS= read -r repo; do
    if [[ -n $repo ]] && [[ -d $repo/.git ]]; then printf '%s\n' "$repo"; fi
  done <"$file"
}
```

- [ ] **Step 2: register in `cmd_new`** (after `repo=$(main_checkout)`) and in
  `cmd_ls`'s single-repo path:

```bash
  register_repo "$repo"
```

- [ ] **Step 3: implement `--all` in `cmd_ls`**, replacing the `die`

```bash
  if [[ $all -eq 1 ]]; then
    local found=0 repo
    while IFS= read -r repo; do
      print_repo_group "$repo"
      found=1
    done < <(registered_repos)
    if [[ $found -eq 0 ]]; then
      info "no repos registered yet - run wtx ls or wtx new inside one"
    fi
    return 0
  fi
```

- [ ] **Step 4: check it**

```bash
W=~/dev/XandruDavid/wtx/bin/wtx
cat "${XDG_STATE_HOME:-$HOME/.local/state}/wtx/repos" 2>/dev/null || echo "(none yet)"

cd ~/dev/myapp && "$W" ls >/dev/null   # registers
cd ~/dev/XandruDavid/wtx && "$W" ls >/dev/null           # registers
cat "${XDG_STATE_HOME:-$HOME/.local/state}/wtx/repos"    # -> two paths
cd /tmp && "$W" ls --all                                 # -> two groups, works outside a repo

# a stale entry is dropped, not an error
printf '%s\n' /tmp/deleted-repo >>"${XDG_STATE_HOME:-$HOME/.local/state}/wtx/repos"
"$W" ls --all                                            # -> still two groups
make -C ~/dev/XandruDavid/wtx check
```

- [ ] **Step 5: document the registry in `README.md`**, under Usage:

```markdown
`wtx ls --all` lists every repo wtx has seen. It learns about a repo the first
time you run `wtx ls` or `wtx new` inside it, and remembers in
`~/.local/state/wtx/repos`. Delete that file to forget everything.
```

- [ ] **Step 6: commit**

```bash
git add bin/wtx README.md
git commit -m "feat: add wtx ls --all across registered repos"
```

---

### Task 10: Clean up the smoke tests

- [ ] **Step 1: remove the worktree Task 6 made in the real repo**

```bash
cd ~/dev/myapp && wtx rm wtx-smoke-test --force
git branch -D wtx-smoke-test    # wtx will not do this for you, by design
```

- [ ] **Step 2: remove the scratch repo**

```bash
rm -rf "${TMPDIR:-/tmp}/wtx-scratch"
```

- [ ] **Step 3: install for real and use it once from `$PATH`**

```bash
ln -s ~/dev/XandruDavid/wtx/bin/wtx ~/.local/bin/wtx
# ~/.local/bin is NOT on this machine's PATH yet. Add this to ~/.zshrc:
#   export PATH="$HOME/.local/bin:$PATH"
```

Then open a new shell and confirm it is picked up:

```bash
which wtx        # -> /Users/you/.local/bin/wtx
wtx --version    # -> wtx 0.0.0-alpha
```

Nothing to commit in this task.

## 7. Distribution

- **Install:** by hand, documented in the README. Symlink `bin/wtx` into
  `~/.local/bin` (or `~/bin`), so `git pull` in this repo updates the command.
  No `install.sh`.
- **`~/.local/bin` exists on this machine but is not on `$PATH`.** The README
  has to say so, with the `~/.zshrc` line.
- **Versioning:** none. `WTX_VERSION="0.0.0-alpha"`, hardcoded, bumped by hand
  if ever. No tags, no releases, no `CHANGELOG.md`.
- **No `wtx upgrade`.** `git pull` in this repo is the upgrade.
- **No CI.** `make check` before committing is the gate.

## 8. Rejected options, and why

- **Copying `node_modules` instead of reinstalling.** All pnpm symlinks are
  relative and the disk is APFS, so `cp -Rc` would clone 2.5G at no real cost.
  But `node_modules/.bin/*` are generated shims with the absolute repo path
  baked into `NODE_PATH`, so a copy silently points the new worktree's binaries
  at the main checkout. Path-keyed caches like `.vite` have the same problem.
  Both are fixed by running `pnpm install` — which is what the copy was avoiding.
  pnpm already hardlinks from `~/Library/pnpm/store/v10`, so a cold install is
  not a network install.
- **Giving new branches an upstream of `origin/<branch>`** by setting
  `branch.<name>.remote` and `branch.<name>.merge` by hand. **Decided against.**
  You were open to it "only if this generates no weird errors or behaviours" —
  it does. Tested: until you push, every `git status` says *"Your branch is
  based on 'origin/<branch>', but the upstream is gone"*, and VSCode's git panel
  shows the same. So branches start with **no upstream**, which is how you
  already work: `git push` fails once with the `--set-upstream` line to copy.
- **Setting `push.default = current`** so a bare `git push` creates
  `origin/<branch>` with no upstream and a clean `git status`. Verified to work,
  but it is a change to *your* git config, not something a worktree tool should
  make, and you said the copy-paste flow is fine as is. Mentioned here only so
  the option is not lost.
- **Resolving the base as `origin/main` only.** Rejected once it was clear
  teammates and friends are in scope. Tested a `master`-default repo that also
  had an abandoned `main` branch: `origin/main` branches off the dead one,
  `origin/HEAD` correctly picks `origin/master`. With no config file, the
  alternative was typing `--from origin/master` on every single `wtx new`.
- **Letting git set the upstream itself.** Verified: without `--no-track`,
  `git worktree add -b foo <dest> origin/main` prints *"branch 'foo' set up to
  track 'origin/main'"*. A later `git push` would then aim at `main`.
- **Finding worktrees by scanning the filesystem.** `find $HOME -maxdepth 5`
  with `node_modules`, `Library` and `.git` pruned took **1 minute 17 seconds**
  on this machine, and matched `~/.claude/projects/...-worktrees` as a false
  positive. Scanning `~/dev` is fast, but hardcoding someone's dev directory is
  worse than a registry. Rejected in favour of §4's registry.
- **Rebuilding the worktree path from the name**, as the old scripts did. The
  author's own repo has a worktree at `...-fix-lint-naming` whose
  branch is `fix-lint-exports`. `--parent` makes it worse. `rm` and
  `ls` ask git instead.
- **A generated `.vscode/tasks.json` with a `folderOpen` task.** That was the
  only way to land a Claude session in VSCode's *integrated* terminal, and it
  needed an explicit `nvm use` because a task shell does not apply `.nvmrc`.
  Dropped: `wtx new` starts no Claude session, and running the install in the
  script instead inherits your shell's environment, where nvm's node is already
  on `$PATH`. It also would have dirtied any repo that tracks `.vscode/`.
- **A config file** (`.wtxrc`, TOML, `git config wtx.*`). Flags plus two
  environment variables cover everything asked for. Revisit when there is a
  setting that genuinely cannot be a flag.
- **Deleting the branch on `rm`**, with the old "only if it is an ancestor of
  `origin/main`" rule, or a squash-merge check via `gh pr view`. `wtx` creates
  branches; it does not manage them. `rm` only checks that your commits are on
  a remote.
- **An interactive prompt on `wtx rm`.** The old script asked "remove anyway?".
  Now it prints what is in the way and exits, and you decide with `--force`.
  Scriptable, and no accidental `y`.
- **`jq` and `gh` as dependencies.** Neither is needed once `tasks.json`
  generation and PR checks are gone. Fewer things for a teammate to install.
- **`git wtx <cmd>`** via a `git-wtx` name, a `wt` alias, and auto-generated
  worktree names. Not wanted.

## 9. Decisions

Nothing is open. Every question raised while writing this plan has an answer
below; the plan implements all of them. Re-open one by editing this section.

### Resolved

- **A repo with no remote branches off local `main`.** Found by running the
  assembled tool: with only `origin/*` in the lookup, `wtx new` failed in any
  local-only repo — including this one, which has no remote yet, so wtx could
  not be used on itself. `default_base` now falls through to local `main`, then
  `HEAD`. The branch still gets no upstream, since there is no remote to track.
- **`wtx ls` shows the main checkout**, tagged `(main checkout)`, so you can see
  whether it is dirty or behind before starting new work.
- **Install detection stays at six lockfiles** — pnpm, bun, yarn, npm, uv, cargo
  — and a repo matching none now prints "no lockfile found, skipping dependency
  install" rather than doing nothing silently. More languages when someone needs
  one; see §10.
- **`--from` stays a documented flag.** Once the base auto-resolves via
  `origin/HEAD`, `--from` is no longer an error escape hatch — it is the way to
  branch off something else on purpose (`wtx new hotfix --from origin/release/2.1`).
  That deserves to be in `wtx help`.
- **`wtx new` prints the path on stdout.** Verified use: `cd "$(wtx new foo)"`
  drops you in the new worktree in one command. Costs nothing, and it is why
  every message goes to stderr.
- **A missing `code` is a warning, not a failure.** The worktree is real, valid
  git, and its path is still printed; only the window is missing.
- **A worktree outside its repo's parent prints its absolute path.** Checked:
  `${path#"$parent"/}` simply does not match, so the row shows the full path
  rather than a `../../..` mess. No special handling needed.
- **Base ref** → `origin/HEAD`, then `origin/main`, then error. §3.
- **Upstream on new branches** → none (`--no-track`). §8.
- **Resume confirmation** → interactive `[y/N]`, `--resume` skips it. §3.
- **`±` column base** → follows the same default-branch resolution as `new`, and
  the header names it. Settled by the two decisions above: with no upstream on
  wtx branches, an upstream-relative count would always be empty.
- **Installing dependencies** → always, on both new and resume, with no skip
  flag. Q22 stands even though resume now exists.
- **A failed install** → warn and carry on. The worktree is valid git and the
  editor still opens; only the install is missing, and you can rerun it there.
- **`rm` in a repo with no remote** → skip the unpushed check and say so, since
  every commit would otherwise count as unpushed. The uncommitted-changes gate
  still applies.
- **`.worktreeinclude` matching a directory** → copy it whole, modes preserved.
  Verified: a `600` key stays `600` and symlinks stay symlinks.

## 10. Later ideas

Parked deliberately, with the reason.

- **Starting a Claude session in the new worktree.** The wanted behaviour is a
  session in VSCode's *integrated* terminal, which needs a `folderOpen` task
  (§8) or something better. Needs a real answer before any code.
- **Configurable editor.** `$EDITOR`/`$VISUAL`, or Cursor and JetBrains. VSCode
  is hardcoded until a second editor is actually needed.
- **zsh completions.** What they are: a file that tells zsh what `wtx ` can be
  followed by, so Tab offers `new`/`rm`/`ls` and then your actual worktree
  names. Shipped as a `_wtx` file installed into a directory on `$fpath`.
  Worth doing once the subcommands stop changing — `wtx rm <Tab>` completing
  real worktree names is the payoff.
- **More install detection.** poetry, bundler, go modules, composer, mix, and
  repos whose lockfile sits in a subdirectory rather than the root. Each is a
  couple of lines in `run_setup` and only fires when that lockfile exists, so
  add them the first time someone hits one rather than guessing now.
- **Narrowing the fetch.** `wtx new` runs `git fetch --quiet origin`, which
  fetches everything. `git fetch origin main` would be faster. Do it if the
  fetch becomes the slow part.
- **`ls` speed.** Each row runs `git status --porcelain`, `rev-list` and
  `log -1`. Measured at **1.0s** for two repos and four worktrees, almost all of
  it `git status` on a big monorepo. Fine now; `--all` over a dozen repos would
  drag. If it does, drop `git status` unless `--dirty` is asked for.
- **Tests.** `bats-core`, with throwaway repos in `$TMPDIR` and a fake `code`
  on `$PATH`. The `scratch()` helper in §6 is most of the fixture already.
- **CI.** GitHub Actions running `make check`. Cheap, but there is no second
  contributor yet.
- **A real language.** Go or Rust for a single distributable binary, if this
  ever needs to reach machines where cloning the repo is not the install.
- **Everything explicitly declined in §2** — `sync`, `open`, `cd`, `doctor`,
  `prune`, `exec`, `config`, bulk removal, PR integration, Jira lookups.
