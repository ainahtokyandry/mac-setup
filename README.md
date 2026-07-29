# mac-setup

Installers for my personal macOS tools. One command clones each repository, builds it, and
puts it where it belongs — so a fresh Mac is set up without walking through three separate
READMEs.

| Tool | What it does | Repository |
| --- | --- | --- |
| **storage-bar** | Free disk space in the menu bar, as `free / total` | [ainahtokyandry/storage-bar](https://github.com/ainahtokyandry/storage-bar) |
| **claude-usage** | The three Claude usage limits in the menu bar, as `5h 42% · 7d 61% · Opus 18%` | [ainahtokyandry/claude-usage](https://github.com/ainahtokyandry/claude-usage) |
| **job-search** | A scheduled agent that sweeps job boards and writes a dated report | [ainahtokyandry/job-search](https://github.com/ainahtokyandry/job-search) |

Each row links to the project's own repository, where the full documentation lives.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools, which provide `git`, `swiftc` and `codesign`:
  ```sh
  xcode-select --install
  ```
- [Claude Code](https://claude.com/claude-code), signed in — needed by
  [claude-usage](https://github.com/ainahtokyandry/claude-usage) (it reads the token the CLI
  keeps in the login keychain) and by
  [job-search](https://github.com/ainahtokyandry/job-search) (the CLI does the searching).
  `storage-bar` does not need it.

## Install

Everything lives in `install.sh` — one file, no supporting scripts, nothing to clone first:

```sh
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/ainahtokyandry/mac-setup/main/install.sh)"
```

Use that form rather than `curl … | zsh`. A pipe occupies stdin, and job-search's setup asks
questions that need the terminal. Arguments go after the command string, past a placeholder
that lands in `$0`:

```sh
zsh -c "$(curl -fsSL …/install.sh)" install --dry-run storage-bar
```

With the file already on disk it is the same script:

```sh
./install.sh
```

Either way, that installs all three. Name one or more tools to install just those:

```sh
./install.sh storage-bar claude-usage
```

Options:

| Option | Effect |
| --- | --- |
| `-d, --dir DIR` | Where checkouts live (default `$HOME/Projects`) |
| `-u, --update` | `git pull --ff-only` in existing checkouts before building |
| `-l, --login-items` | Register the menu bar apps to open at login |
| `-N, --no-launch` | Install without opening the apps |
| `-n, --dry-run` | Print every command instead of running it |
| `-h, --help` | Usage |

A dry run first is the cheap way to see exactly what will happen:

```sh
./install.sh --dry-run
```

### What it does to your machine

- **Clones** each repository into `$HOME/Projects` (or `--dir`). An existing checkout of the
  same repository is reused wherever it already sits under that directory, whatever the
  folder is called — nothing is re-cloned, and nothing is pulled unless you pass `--update`.
- **Builds** the two menu bar apps from source with `swiftc -O` and signs them ad hoc with
  `codesign`. The signing step is not optional: an unsigned bundle will not launch on recent
  macOS versions.
- **Installs** the bundles into `/Applications`, falling back to `~/Applications` when
  `/Applications` is not writable, stopping any running copy first. No `sudo` anywhere.
- **Launches** them, unless `--no-launch`.
- **Hands over** to [job-search](https://github.com/ainahtokyandry/job-search)'s own
  `setup.sh`, which asks four questions — schedule, profile, background agent, menu bar
  indicator — and installs the `launchd` agents.

One thing the installer cannot avoid: the three **tool** repositories still get cloned. They
ship source rather than prebuilt binaries, so the build needs `main.swift` locally, and
job-search's `launchd` agent runs `run-search.sh` out of a permanent checkout.

## Layout

```
install.sh   Everything: option parsing, preflight checks, checkout reuse,
             bundle install, and one function per tool
README.md    This file
```

Every setting has an environment variable behind the flag, which is what makes the one-liner
composable: `MAC_SETUP_SRC_DIR`, `UPDATE`, `LOGIN_ITEMS`, `LAUNCH`, `DRY_RUN`.

```sh
MAC_SETUP_SRC_DIR=~/src LAUNCH=0 ./install.sh
```

## Rebuilding after a change

Re-running the installer rebuilds from the checkout and replaces the installed bundle, so
after editing a project's source:

```sh
./install.sh storage-bar
```

To pull upstream changes first, add `--update`:

```sh
./install.sh --update storage-bar
```

## Uninstalling

The menu bar apps are self-contained bundles:

```sh
pkill -x StorageBar;     rm -rf /Applications/StorageBar.app
pkill -x ClaudeUsageBar; rm -rf /Applications/ClaudeUsageBar.app
```

job-search installs `launchd` agents, so it has its own uninstaller, which keeps your reports
and logs:

```sh
cd ~/Projects/job-search && ./uninstall.sh
```

If you added the apps as login items, remove those entries in **System Settings > General >
Login Items & Extensions** as well.
