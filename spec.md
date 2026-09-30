# wtx — Spec

## Idea

wtx makes it cheap to start work in a fresh, isolated copy of a repo, and to
throw it away when done. Each copy is a git worktree on its own branch, placed
next to the repo rather than inside it. The main use is running a coding
session (for example Claude Code) without touching the main checkout.

A new worktree must be ready to work in: the files git ignores but the project
needs (like `.env`) are copied in, dependencies are installed, and an editor
window opens. Being ready matters more than being fast.

wtx is not a git workflow tool. It never deletes branches, and it does not
rebase, merge, push or talk to GitHub.

Users: the author and teammates, on macOS or another unix, using VSCode.

## Commands

- `wtx new <name>` — create a worktree and open it.
- `wtx rm [<name>]` — remove a worktree. The branch stays.
- `wtx ls` — list worktrees. `wtx ls --all` lists them for every known repo.
- `wtx help`, `wtx --version`.

`remove` and `list` are aliases of `rm` and `ls`.

### Rules for every command

- Works from the main checkout or from inside any of its worktrees.
- Normal output is data only: `new` prints the new worktree's path, `ls`
  prints its table. Progress, warnings, errors and questions go to the error
  stream, so `cd "$(wtx new foo)"` works.
- Exit status: 0 success, 1 failure, 2 wrong usage. Running `wtx` with no
  command prints usage and exits 2.
- Errors start with `wtx:`. Colour only in a terminal, and never when
  `NO_COLOR` is set.
- Slow steps say what they are doing, so they don't look stuck.
- No config file. Behaviour is set by flags and a few environment variables.

## `wtx new <name>`

**Naming.** The name is turned into kebab-case (lowercase, dashes) and becomes
the folder name. The branch has the same name, unless `--branch <branch>` gives
another; that one is used as typed (so `feature/x` stays `feature/x`) and must
be a valid branch name.

**Location.** Worktrees go in a folder next to the repo, `<repo>-worktrees/`.
`WTX_PARENT` changes this for every repo; `--parent <dir>` changes it for one
worktree. If the target folder already exists, wtx refuses.

**New branch.** It starts from the repo's default branch as the remote names
it (main, master, develop…), after fetching. A repo without a remote uses its
local main branch. `--from <ref>` picks another starting point. wtx says which
base it used. A failed fetch is only a warning. The new branch has no upstream,
so a first `git push` can never go to the default branch by mistake. A repo
with no commits cannot be branched from; wtx says to pass `--from`.

**Existing branch.**
- Already checked out in a worktree: wtx opens that worktree and prints its
  path. Nothing new is created.
- Not checked out anywhere: wtx asks whether to resume from it. `--resume`
  answers yes. Without a terminal to ask in and without `--resume`, it fails
  and says to pass `--resume`.

**Making it ready.**
1. Copy the files listed in the repo's `.worktreeinclude`.
2. Install dependencies with the project's package manager, detected from its
   lockfile: pnpm, bun, yarn, npm, uv or cargo. If none is found, wtx says so.
   A missing package manager or a failed install is a warning; the worktree is
   still usable.
3. Open a new VSCode window on it. If VSCode is not available, warn.
4. Print the path.

### `.worktreeinclude`

A plain file at the repo root, owned by the repo. One pattern per line, `#`
starts a comment. A pattern that matches a folder copies it whole. File
permissions are kept, so a private key stays private. `certs/` and `certs` mean
the same. No negations.

## `wtx rm [<name>]`

**Finding it.** The name matches either a worktree's folder name or its branch,
as typed or in kebab-case. Branches get renamed and folders don't, so both are
checked. No match: fail and suggest `wtx ls`. Several matches: fail and list
them. The main checkout can never be removed.

**Picking it.** With no name, in a terminal, wtx shows the repo's worktrees
(never the main checkout) as the same table as `ls`, fitted to the terminal
the same way, and the user picks:
- with a fuzzy finder installed, a searchable list where several can be
  picked at once;
- otherwise a numbered menu, one pick.

Outside a terminal, the name is required. Cancelling is not an error:
nothing is removed and wtx exits 0.

**Safety checks**, skipped with `--force`:
- uncommitted changes: show them and stop;
- commits that are on no remote: show them and stop. In a repo with no remote
  this check can't work, so wtx skips it and says so.

There is no "are you sure" question: either you pass `--force` or you don't.
When several worktrees were picked, one failing its checks doesn't stop the
others, and the exit status reports how many were left.

**Removing.** The folder is deleted and git forgets the worktree. If the folder
was already gone, git just forgets it. wtx says the branch was kept, and warns
if the worktree was locked.

## `wtx ls [--all]`

One group per repo. Each row is a worktree:

| Column | Shows |
|---|---|
| NAME | the folder name, which is what `wtx rm` takes. A worktree outside the usual folder shows its full path, so it stands out. |
| BRANCH | the branch, or `(detached <short commit>)` when there is none. The main checkout's is marked `*`. |
| STATE | `clean`, `dirty`, or `gone` if the folder is missing; `,locked` added when locked |
| ±main | commits ahead/behind the default branch (named after it: ±main, ±master…). Not the upstream: new branches have none. |
| AGE | time since the last commit, short: `now`, `5m`, `2h`, `3d`, `2w`, `4mo`, `1y` |

The group header names the repo and where it is, and where its worktrees go
when that is not the usual `<repo>-worktrees/` folder next to it.

**Fitting the terminal.** When the table is wider than the terminal, NAME and
BRANCH are shortened with `…`, the longer one first, down to 12 characters. A
full path is shortened from the start so the folder name stays visible. If it
still doesn't fit, lines wrap. No column is ever dropped.

**Piped output** is not shortened: full paths, full branch names, long times
("3 days ago", in a LAST COMMIT column), and the main checkout labelled in words.

**All repos.** git has no list of repos, so wtx keeps one: a repo is added the
first time `wtx new` or `wtx ls` runs in it. `--all` lists every repo on it
that still exists. Deleting that list makes wtx forget them all.

## Not supported

Windows, bare repos, editors other than VSCode, deleting branches, starting a
coding session automatically. Repos with many submodules are untested.

## Open questions

- A cleanup command that offers only worktrees that are safe to remove.
- Shell completion for worktree names.
- Picking several from the numbered menu.
