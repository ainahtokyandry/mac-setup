# mac-setup

**MacBar** — one menu bar item for several small tools, and the installer that puts it there.
What used to be three separate menu bar items, three apps and three icons, is now one item with
three sections.

```
⌾ 118 GB · 42·61·18% · ◷ Mon 08:00
```

The tools themselves are not here. This repository holds the **host** — the status item, the
dropdown, and the contract a section is written against — and each section stays in its own
repository:

| Section | What it shows | Repository |
| --- | --- | --- |
| **Storage** | Free space on the boot volume | [ainahtokyandry/storage-bar](https://github.com/ainahtokyandry/storage-bar) |
| **Claude usage** | The three Claude usage limits | [ainahtokyandry/claude-usage](https://github.com/ainahtokyandry/claude-usage) |
| **Job search** | The next scheduled run, and whether one is in flight | [ainahtokyandry/job-search](https://github.com/ainahtokyandry/job-search) |

So each tool keeps its own history, README and issues, and improving one means editing that
repository — not this one. MacBar is built from whichever sections are checked out, and pulling
a section and rebuilding is one command:

```sh
./install.sh --update macbar
```

Any section can be dropped from the menu bar line under **Menu Bar** in the dropdown, and
**Compact Display** in the same submenu spells the readings out in full:
`118 GB / 494 GB · 5h 42% · 7d 61% · Opus 18% · ◷ Mon 08:00`.

## How the split works

A section is one file declaring one class that conforms to `BarSection`:

```swift
final class StorageSection: NSObject, BarSection {
    let name = "Storage"                                  // dropdown header, toggle label
    let showKey = "showStorage"                           // its own preference key
    func activate(onUpdate: @escaping () -> Void)         // start polling
    func refresh(force: Bool)                             // the menu is opening
    func titleSegments(compact: Bool) -> [Segment]        // its part of the menu bar title
    func menuRows() -> [NSMenuItem]                       // its block of the dropdown
    func snapshot(_ completion: @escaping ([String], Bool) -> Void)   // for --print
}
```

It polls on its own clock, contributes a run or two to the shared title, and owns a block of the
dropdown. It never touches the status item: it asks for a redraw, and the host draws. A section
whose subject is not on this Mac — job search with no checkout — reports `isAvailable == false`
and vanishes, so MacBar comes up one section short rather than one section wrong.

`menubar/build.sh` finds sections by convention under `$HOME/Projects` (or `MACBAR_SRC_DIR`):

```
<repo>/*Section.swift
<repo>/menubar/*Section.swift
```

A file only counts when it declares a `BarSection`, so an unrelated match in another project is
passed over. The build then generates the list of what it found and compiles it in. Adding a
fourth tool means writing one file in a new repository and cloning it — no edit here.

Two constraints worth knowing, both from `swiftc`:

- **Sections are single-file, named after their type.** All sections compile into one module,
  and basenames within a module have to be distinct, so two repositories could not both offer
  `Section.swift`.
- **A section keeps its declarations inside its own type.** One module also means one namespace:
  a top-level `Limit` or `Config` in one section would be free to collide with a sibling's.

Each section repository can still build an app of its own — `StorageBar.app` is MacBar with a
list of one — by compiling against a checkout of this repository. That direction of dependency
is deliberate: it is what keeps a single definition of the contract, rather than a copy of it
per repository, drifting.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools, which provide `git`, `swiftc` and `codesign`:
  ```sh
  xcode-select --install
  ```
- [Claude Code](https://claude.com/claude-code), signed in — needed by the Claude usage section
  (it reads the OAuth token the CLI keeps in the login keychain) and by job-search (the CLI does
  the searching). The storage section needs nothing.

## Install

`install.sh` is one file with no supporting scripts of its own, so it runs straight off the
network:

```sh
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/ainahtokyandry/mac-setup/main/install.sh)"
```

Use that form rather than `curl … | zsh`. A pipe occupies stdin, and job-search's setup asks
questions that need the terminal. Arguments go after the command string, past a placeholder that
lands in `$0`:

```sh
zsh -c "$(curl -fsSL …/install.sh)" install --dry-run macbar
```

With the repository already cloned it is the same script:

```sh
./install.sh
```

Either way, that installs both tools — job-search first, then MacBar. Name one to install just
that:

```sh
./install.sh macbar
```

Options:

| Option | Effect |
| --- | --- |
| `-d, --dir DIR` | Where checkouts live (default `$HOME/Projects`) |
| `-u, --update` | `git pull --ff-only` in existing checkouts before building |
| `-l, --login-items` | Register MacBar to open at login |
| `-N, --no-launch` | Install without opening the app |
| `-n, --dry-run` | Print every command instead of running it |
| `-h, --help` | Usage |

A dry run first is the cheap way to see exactly what will happen:

```sh
./install.sh --dry-run
```

### What it does to your machine

- **Clones** the section repositories into `$HOME/Projects` (or `--dir`). An existing checkout
  of the same repository is reused wherever it already sits under that directory, whatever the
  folder is called — nothing is re-cloned, and nothing is pulled unless you pass `--update`. A
  section that cannot be cloned is left out of the build rather than stopping it.
- **Builds** MacBar with `swiftc -O` — this repository's host plus every section found — and
  signs it ad hoc with `codesign`. The signing step is not optional: an unsigned bundle will not
  launch on recent macOS versions.
- **Installs** the bundle into `/Applications`, falling back to `~/Applications` when
  `/Applications` is not writable, stopping any running copy first. No `sudo` anywhere.
- **Retires** the apps MacBar replaces: it stops `StorageBar`, `ClaudeUsageBar` and
  `JobSearchBar`, deletes any of their bundles under `/Applications` or `~/Applications`,
  removes their login items, and unloads job-search's `com.jobsearch.menubar` agent. A copy
  still sitting inside its own checkout is reported rather than deleted — that one is yours to
  remove.
- **Records** where the job-search checkout is, with
  `defaults write local.macbar jobSearchDir …`, so that section works wherever the checkout
  sits.
- **Launches** MacBar, unless `--no-launch`.
- **Hands over** to [job-search](https://github.com/ainahtokyandry/job-search)'s own `setup.sh`,
  which asks four questions — schedule, profile, background agent, menu bar indicator — and
  installs the `launchd` agents. Question 4 defaults to **no**, which is the right answer when
  MacBar is installed: it already has a job search section, and saying yes means a second item
  in the menu bar.

## Layout

```
menubar/
  main.swift        entry point: Host.run(sections:)
  Host.swift        startup and --print, shared with standalone section apps
  Controller.swift  the one status item: title, dropdown, section toggles
  Support.swift     the contract: BarSection, Segment, Palette, Fmt, MenuKit
  Info.plist        the bundle, LSUIElement so there is no Dock icon
  build.sh          finds sections, generates their list, builds and signs
install.sh          option parsing, preflight, checkouts, install, retire
README.md           this file
```

Nothing under `menubar/` knows what is being measured. `Info.plist` and `Support.swift` are the
only files that would change if MacBar were renamed.

Every installer setting has an environment variable behind the flag, which is what makes the
one-liner composable: `MAC_SETUP_SRC_DIR`, `UPDATE`, `LOGIN_ITEMS`, `LAUNCH`, `DRY_RUN`.

```sh
MAC_SETUP_SRC_DIR=~/src LAUNCH=0 ./install.sh
```

`menubar/build.sh` takes `MACBAR_SRC_DIR` to choose where sections are looked for, and
`MACBAR_SECTIONS` to name them explicitly, separated by colons — which is the quick way to build
with a subset:

```sh
MACBAR_SECTIONS=~/Projects/StorageBar/StorageSection.swift ./menubar/build.sh --run
```

## Design notes

Both surfaces the app draws on are translucent, which rules out two habits. Colours come from
`Palette` rather than `NSColor.systemOrange` and friends, which are tuned for solid backgrounds
and wash out over a light one; and a row that carries a warning stays *enabled*, because macOS
draws a disabled item at reduced alpha. `systemOrange` on a disabled row reaches about 1.4:1
against a light menu — `Palette.warning` on an enabled one is above 5:1 in both appearances.

Sections poll on their own clocks and can land in the same turn of the run loop, so redraws are
coalesced into one. The dropdown is rebuilt on the way open, and again in place only while it is
on screen — so a fetch that lands under an open menu is reflected without disturbing a
highlighted row.

## Working on MacBar

The host and the sections are separate checkouts, so there are two short loops. For a change to
the host:

```sh
./menubar/build.sh --run       # build, sign, relaunch
```

For a change to a section, the same command rebuilds MacBar around it — `build.sh` reads that
section straight out of its checkout, so there is nothing to copy or publish first.

The readings are also available without the menu bar, which is the quick way to check formatting
after a change:

```sh
/Applications/MacBar.app/Contents/MacOS/MacBar --print
```

```
Storage
  Available:  118 GB
  Used:       376 GB (76%)
  Total:      494 GB

Claude usage
  Session (5h)         ██████░░░░░░░░  42%  resets 14:29 (in 3h 23m)
  Weekly (all models)  █████████░░░░░  61%  resets Fri 31 Jul, 11:59 (in 1d 0h)
  Weekly (Opus)        ███░░░░░░░░░░░  18%  resets Fri 31 Jul, 11:59 (in 1d 0h)

Job search
  Idle
  Next run:  Mon 3 Aug, 08:00  (in 2d 20h)
  Last run:  Fri 31 Jul, 15:00  (20h 6m ago)
  Latest:    job-search-2026-07-31.md
```

It exits non-zero if any section could not take its reading.

To rebuild and reinstall through the installer instead:

```sh
./install.sh macbar
```

### Your editor will show errors that are not there

Opening any of these repositories in an editor gives a wall of red:

```
Cannot find type 'BarSection' in scope
Cannot find 'Palette' in scope
Cannot find 'StorageSection' in scope
```

None of it is real. The module is assembled at build time out of four checkouts —
`menubar/` here, plus one file from each section repository — and SourceKit-LSP has no manifest
describing that, so it type-checks each file on its own, where of course the other half is
missing. `menubar/build.sh` is the source of truth; if it compiles, the code is fine.

A `Package.swift` would not fix it either, because there is no single package to describe: the
module spans repositories by design. Live with the squiggles, or turn Swift diagnostics off for
these folders.

## Uninstalling

MacBar is a self-contained bundle:

```sh
pkill -x MacBar
rm -rf /Applications/MacBar.app
defaults delete local.macbar
```

job-search installs `launchd` agents, so it has its own uninstaller, which keeps your reports
and logs:

```sh
cd ~/Projects/job-search && ./uninstall.sh
```

If you added MacBar as a login item, remove that entry in **System Settings > General > Login
Items & Extensions** as well.
