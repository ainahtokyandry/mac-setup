# mac-setup

**MacBar** — one menu bar item for several small tools, and the installer that puts it there.
What used to be three separate menu bar items, three apps and three icons, is now one item with
a section for each, plus a fourth for today's meetings.

```
⌾ 118 GB · 42·61·18% · ○ 14:00 · ◷ Mon 08:00
```

The tools themselves are not here. This repository holds the **host** — the status item, the
dropdown, and the contract a section is written against — and each section stays in its own
repository:

| Section | What it shows | Repository |
| --- | --- | --- |
| **Storage** | Free space on the boot volume | [ainahtokyandry/storage-bar](https://github.com/ainahtokyandry/storage-bar) |
| **Claude usage** | The three Claude usage limits | [ainahtokyandry/claude-usage](https://github.com/ainahtokyandry/claude-usage) |
| **Meetings** | Today's meetings, a click to join the call, a reminder 30 minutes before | [ainahtokyandry/meetings-bar](https://github.com/ainahtokyandry/meetings-bar) |
| **Job search** | The next scheduled run, and whether one is in flight | [ainahtokyandry/job-search](https://github.com/ainahtokyandry/job-search) |

So each tool keeps its own history, README and issues, and improving one means editing that
repository — not this one. Running the installer again is an update: it fast-forwards the
checkout of every section you chose and rebuilds MacBar around them, so picking up the latest of
every section is one command:

```sh
./install.sh macbar
```

The installer asks which sections to include, and any section built in can be switched off later
under **Sections** in the dropdown. A section that is off is gone from the menu bar line and from
the dropdown, and stops running until it is switched back on.
Unticking **Compact Display** spells the readings out in full:
`118 GB / 494 GB · 5h 42% · 7d 61% · Opus 18% · ○ 14:00 Design review · ◷ Mon 08:00`.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools, which provide `git`, `swiftc` and `codesign`:
  ```sh
  xcode-select --install
  ```
- [Claude Code](https://claude.com/claude-code), signed in — needed by the Claude usage section
  (it reads the OAuth token the CLI keeps in the login keychain) and by job-search (the CLI does
  the searching). The storage section needs nothing.
- For the meetings section: access to your calendars and permission to send notifications, both
  asked for when MacBar first opens. It reads whatever the Calendar app syncs, so add Google or
  Exchange accounts under **System Settings > Internet Accounts**.

## Install

`install.sh` is one file with no supporting scripts of its own, so it runs straight off the
network:

```sh
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/ainahtokyandry/mac-setup/main/install.sh)"
```

Use that form rather than `curl … | zsh`. A pipe occupies stdin, and both the section questions
and job-search's setup need the terminal. Arguments go after the command string, past a
placeholder that lands in `$0`:

```sh
zsh -c "$(curl -fsSL …/install.sh)" install --dry-run macbar
```

With the repository already cloned it is the same script:

```sh
./install.sh
```

Run that way, the installer and the host come from your clone as it stands: an update pulls the
sections, not the clone it runs from, so `git pull` there first to pick up changes to this
repository. The one-liner always runs the latest of both.

Either way, that installs both tools — job-search first, then MacBar. Name one to install just
that:

```sh
./install.sh macbar
```

### Choosing sections

Installing MacBar starts by asking which sections it should have, one question each, before
anything is cloned:

```
==> Which sections should MacBar have? Return keeps the answer in capitals.
  Storage       free space on the boot volume            [Y/n]
  Claude usage  the three Claude usage limits            [Y/n]
  Meetings      today's meetings; needs calendar access  [Y/n] n
  Job search    the next scheduled job search run        [Y/n]
```

A section left out is not cloned for MacBar and not built in, even when its repository is there
for another reason, and the old app it replaced, if any, is left where it is. The answers are
remembered, as `skippedSections` in MacBar's preferences, so the next install asks with the same
answers as its defaults, and uses them as they are when there is no terminal to ask in. The
first install defaults to all four.

`--sections` answers up front, with any of `storage`, `claude-usage`, `meetings` and
`job-search`, comma separated, or `all`:

```sh
./install.sh --sections storage,meetings macbar
```

A section in `~/MacBar` that is none of the four — one written for this Mac alone — is built in
whatever the answers.

Options:

| Option | Effect |
| --- | --- |
| `-s, --sections LIST` | MacBar sections to include, instead of being asked |
| `-f, --fresh` | Empty `$HOME/MacBar` into the Trash first, and start from fresh clones |
| `-l, --login-items` | Register MacBar to open at login |
| `-N, --no-launch` | Install without opening the app |
| `-n, --dry-run` | Print every command instead of running it |
| `-h, --help` | Usage |

A dry run first is the cheap way to see exactly what will happen:

```sh
./install.sh --dry-run
```

### What it does to your machine

- **Clones** the repositories of the sections you chose into `$HOME/MacBar`. An existing
  checkout is reused when it sits in its usual folder there — `StorageBar` or `storage-bar`,
  `claude-usage`, `meetings-bar`, `job-search` — so running the installer again is an update,
  not a reinstall: each checkout is fast-forwarded, and files of your own in them, such as
  job-search's profile and reports, stay where they are. A checkout that cannot be
  fast-forwarded — no network, or local changes in the way — is built as it stands, with a
  warning. A checkout in a folder by any other name is not looked for: a second copy is cloned
  beside it, and the build then stops on the duplicate section, so rename the folder first. A
  section that cannot be cloned is left out of the build rather than stopping it.
- **Empties** `$HOME/MacBar` first, only with `--fresh`. Everything in it goes to the Trash —
  put back from there anything you miss — with two exceptions. The mac-setup checkout the
  installer is running from stays, if it is in there. And job-search's personal files, the ones
  git ignores there (profile, config, reports, logs, CVs), are copied into a fresh clone at the
  same path, so its scheduled agent carries on. That clone is made before anything moves, so a
  failed clone leaves the folder as it was; and while a job search is running the install stops
  instead, with nothing moved. Every other section is then cloned afresh, so `--fresh` wants a
  working connection: a section that fails to clone is left out of the rebuilt MacBar.
- **Builds** MacBar with `swiftc -O` — this repository's host plus every section found, less the
  ones left out — and signs it ad hoc with `codesign`. The signing step is not optional: an
  unsigned bundle will not launch on recent macOS versions.
- **Installs** the bundle into `/Applications`, falling back to `~/Applications` when
  `/Applications` is not writable, stopping any running copy first. No `sudo` anywhere.
- **Retires** the apps MacBar's sections replace, each only when its section is included: it
  stops `StorageBar`, `ClaudeUsageBar` and `JobSearchBar`, deletes any of their bundles under
  `/Applications` or `~/Applications`, removes their login items, and unloads job-search's
  `com.jobsearch.menubar` agent. A copy still sitting inside its own checkout is reported rather
  than deleted — that one is yours to remove.
- **Records** which sections were left out, with
  `defaults write local.macbar skippedSections …`, and, when the job search section is included,
  where the job-search checkout is, with `defaults write local.macbar jobSearchDir …`, so that
  section works wherever the checkout sits.
- **Launches** MacBar, unless `--no-launch`.
- **Hands over** to [job-search](https://github.com/ainahtokyandry/job-search)'s own `setup.sh`,
  which asks four questions — schedule, profile, background agent, menu bar indicator — and
  installs the `launchd` agents. Question 4 defaults to **no**, which is the right answer when
  MacBar is installed with its job search section: saying yes means a second item in the menu
  bar. With that section left out, yes is how the job search gets into the menu bar at all.

## Layout

```
menubar/
  main.swift        entry point: Host.run(sections:)
  Host.swift        startup and --print, shared with standalone section apps
  Controller.swift  the one status item: title, dropdown, a switch per section
  Support.swift     the contract: BarSection, Segment, Palette, Fmt, MenuKit
  Info.plist        the bundle: LSUIElement so there is no Dock icon, and the calendar usage string
  build.sh          finds sections, generates their list, builds and signs
install.sh          options, section choice, preflight, checkouts, --fresh, install, retire
README.md           this file
```

Nothing under `menubar/` knows what is being measured. If MacBar were renamed, `Info.plist`,
`Support.swift` and `build.sh` — the bundle and binary it builds, and the checkout folder it
looks in — are the files there that would change; the other Swift files mention it only in
comments.

Every installer setting has an environment variable behind the flag, which is what makes the
one-liner composable: `MAC_SETUP_SECTIONS`, `FRESH`, `LOGIN_ITEMS`, `LAUNCH`, `DRY_RUN`.

```sh
MAC_SETUP_SECTIONS=storage,claude-usage LAUNCH=0 ./install.sh
```

`menubar/build.sh` takes `MACBAR_SRC_DIR` to choose where sections are looked for, and
`MACBAR_SECTIONS` to name them explicitly, separated by colons — which is the quick way to build
with a subset:

```sh
MACBAR_SECTIONS=~/MacBar/StorageBar/StorageSection.swift ./menubar/build.sh --run
```

`MACBAR_SKIP` works the other way round, leaving sections out by the name of the type they
declare, also separated by colons. It is what the installer passes for the sections you declined,
since a declined section's repository may still be checked out — job-search is a tool as well as
a section:

```sh
MACBAR_SKIP=MeetingsSection:JobSearchSection ./menubar/build.sh --run
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
section straight out of its checkout, so there is nothing to copy or publish first. It looks in
`~/MacBar`, where the installer keeps them; to build from working copies kept elsewhere, point it
there:

```sh
MACBAR_SRC_DIR=~/Projects ./menubar/build.sh --run
```

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

Meetings
  ✓ 09:30–10:00  Standup  Meet: https://meet.google.com/abc-defg-hij
    14:00–15:00  Design review  (in 2h 54m)  Meet: https://meet.google.com/klm-nopq-rst
  Reminder 30 min before each meeting

Job search
  Idle
  Next run:  Mon 3 Aug, 08:00  (in 2d 20h)
  Last run:  Fri 31 Jul, 15:00  (20h 6m ago)
  Latest:    job-search-2026-07-31.md
```

It exits non-zero if any section could not take its reading. A section switched off prints
`switched off under Sections`, which does not count as a failure.

To rebuild and reinstall through the installer instead:

```sh
./install.sh macbar
```

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
cd ~/MacBar/job-search && ./uninstall.sh
```

The checkouts stay in `~/MacBar` until you delete that folder.
job-search keeps its profile, reports and logs inside its checkout, so move out anything you want
to keep before deleting it.

If you added MacBar as a login item, remove that entry in **System Settings > General > Login
Items & Extensions** as well.
