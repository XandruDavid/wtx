# wtx

worktree-extended — git worktrees as repo siblings, ready to work in.

`wtx new fix-the-thing` gives you a fresh worktree next to your repo, on a new
branch off your repo's default branch, with your gitignored `.env` files copied
in, dependencies installed, and a VSCode window open on it.
`wtx rm fix-the-thing` takes the worktree away and leaves the branch alone.
`wtx ls` shows you what you have.

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

New branches start with **no upstream**, so your first `git push` prints the
`--set-upstream` command to copy. That is deliberate: it keeps `git push` from
ever aiming at your default branch by accident.

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
