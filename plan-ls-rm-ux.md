# wtx — Plan: readable `ls`, pick-to-remove `rm`

> **For agentic workers:** implement this plan task by task with
> `superpowers:subagent-driven-development` or `superpowers:executing-plans`.
> Steps use `- [ ]` checkboxes. Tick them as you go — this file is live.
>
> Follows [plan.md](./plan.md) (the initial implementation, complete). Its
> **Global constraints** still apply: bash 3.2, no GNU-only flags, no hard
> dependencies, `shellcheck` + `shfmt` before every commit, Conventional Commits
> straight to `main`.

**Goal:** make `wtx ls` readable on a narrow terminal, make detached worktrees
identifiable, and let `wtx rm` work without typing a worktree name.

---

## 1. Problems

1. **`ls` wraps badly.** `column -t` pads to the widest value in each column and
   ignores the terminal width. On a thin terminal each row wraps back to
   column 0, so the columns stop lining up.
2. **Detached worktrees show `-` as the branch.** `list_worktrees` leaves the
   branch empty for a detached HEAD, so the row gives no hint of what it is.
3. **`rm` needs the name typed exactly.** `ls` is mostly used to decide what to
   remove, but its rows are keyed by branch while `rm` takes the worktree name.

## 2. Decisions

### `ls`

- **Keep every column.** Nothing is dropped for width.
- **Shorten values in this order**, stopping as soon as the table fits:
  1. *Terser values, always on in a terminal:*
     - main checkout marked with `*` in front of the branch, instead of adding
       ` (main checkout)`;
     - short relative time: `2h`, `3d`, `5w`, `4mo`, `1y` instead of
       `2 hours ago`.
  2. *Ellipses, only when still too wide:* cut **BRANCH** and **PATH** (the
     worktree folder) with `…`, the longest first, down to a minimum width
     (about 12 characters each).
  3. *Still too wide:* print it anyway and let the terminal wrap.
- **PATH becomes NAME** (terminal only):
  - the repo header shows the worktrees folder once, e.g.
    `myapp  ~/dev/myapp  →  worktrees in ~/dev/myapp-worktrees/`;
  - worktrees inside `worktree_parent` (respects `$WTX_PARENT`) show only the
    folder name — exactly what `wtx rm` matches on (`find_worktree` compares
    the basename);
  - worktrees elsewhere show their full path with `~` for `$HOME`, so the
    odd ones stand out;
  - the main checkout shows its folder name, marked `*`;
  - NAME is the first column.
- **Width source:** `$COLUMNS`, else `tput cols`, else 80.
- **Piped (stdout not a terminal):** full-length values, no shortening, no
  ellipses, absolute paths — the output as it is today (plus the detached
  label).

### Detached HEAD

- Show `(detached abc1234)` in BRANCH, with the short commit hash, as
  `git branch` does.
- `rm` messages use the same label (`found … (detached abc1234)`).

### `rm` picker

- `wtx rm` with **no name**, in a terminal, opens a picker over the current
  repo's worktrees (the main checkout is never offered).
- **fzf if installed** (`command -v fzf`): fuzzy search, row shows the same state
  as `ls` (state, ±base, last commit), `--multi` so Tab selects several.
- **Otherwise bash `select`**: a numbered menu, one worktree per pick.
- **Not a terminal** (stdin or stderr not a tty): no prompt; keep today's error
  `rm needs a worktree name`.
- Each chosen worktree goes through the same checks as `wtx rm <name>` today
  (uncommitted changes, unpushed branch, `--force` to skip them). With several
  selected, one failing does not stop the rest; exit non-zero at the end if any
  failed.
- No environment variable to choose the picker.

## 3. Open questions

- [ ] Worth adding a cleanup mode (`wtx prune` / `wtx rm --gone`) that offers
  only worktrees that are safe to remove?
- [ ] Shell completion for worktree names (zsh / bash), or does the picker make
  it unnecessary?
- [ ] Should the fallback `select` menu also allow picking several (e.g. `1 3`)?

---

## 4. Tasks

### Task 1 — detached label

- [x] `list_worktrees`: keep the HEAD sha for detached worktrees so callers can
  build `(detached <short sha>)`.
- [x] `ls` and `rm` show the label; `ahead_behind` still prints `-` for it.
- [x] Callers that test `branch == '-'` (e.g. `rm` "kept branch") still work.
- [x] Verify by hand with `git worktree add --detach`.

### Task 2 — terser `ls` values

- [x] `*` marker for the main checkout.
- [x] Short relative time helper (`2h`, `3d`, …), bash 3.2 compatible; from
  `git log -1 --format=%ct` and `date +%s`.
- [x] NAME column: basename inside `worktree_parent`, `~`-abbreviated path
  otherwise; header line names the worktrees folder.
- [x] Only in a terminal; piped output keeps full values and absolute paths.

### Task 3 — fit to width

- [ ] Detect width (`$COLUMNS` → `tput cols` → 80) only when stdout is a tty.
- [ ] Compute column widths in `awk` (no `column` for the tty path, or run
  `column` after truncating) and trim BRANCH / PATH with `…` down to the
  minimum.
- [ ] `…` is multibyte: make sure width math counts it as one column in macOS
  `awk`.
- [ ] Check at 60, 80, 120 columns and with `| cat`.

### Task 4 — `rm` picker

- [ ] No-name path: tty check → fzf (`--multi`) or `select` fallback.
- [ ] Picker rows reuse the `ls` row builder.
- [ ] Refactor the single-worktree removal into a function called once per pick.
- [ ] Multi-pick: continue on failure, non-zero exit at the end.
- [ ] Update `wtx help` and README.

### Task 5 — wrap up

- [ ] `shellcheck` + `shfmt` clean.
- [ ] Resolve or move the open questions above.
