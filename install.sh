#!/bin/zsh
# Installs my personal macOS tools:
#
#   macbar         one menu bar item for disk space, Claude usage, today's
#                  meetings and the job search — built from menubar/ in this
#                  repository, with the sections you choose
#   job-search     https://github.com/ainahtokyandry/job-search
#
# Locally:
#   ./install.sh                  install both, asking which MacBar sections to include
#   ./install.sh macbar           install one
#   ./install.sh -s storage,meetings macbar
#                                 choose the sections up front instead of being asked
#   ./install.sh --dry-run        print the commands instead of running them
#
# Straight off the network, without cloning anything first:
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/ainahtokyandry/mac-setup/main/install.sh)"
#
# Use that form rather than `curl … | zsh`: a pipe occupies stdin, and
# job-search's setup asks questions that need the terminal. Arguments go after
# the command string, past a placeholder that lands in $0:
#   zsh -c "$(curl -fsSL …/install.sh)" install --dry-run macbar

set -euo pipefail

# --------------------------------------------------------------------------- settings

# The folder this script sits in. Taken here at the top level, because inside a
# function zsh sets $0 to the function's name. Run straight off the network there
# is no such folder and this is wherever the command was run from, which counts
# as a host checkout only where menubar/Support.swift is really there.
SCRIPT_DIR="${0:A:h}"

SRC_DIR="$HOME/MacBar"                          # where checkouts live; updated on every run
DRY_RUN="${DRY_RUN:-0}"                         # 1 = print commands, change nothing
FRESH="${FRESH:-0}"                             # 1 = empty $SRC_DIR into the Trash first
LOGIN_ITEMS="${LOGIN_ITEMS:-0}"                 # 1 = register the app to open at login
LAUNCH="${LAUNCH:-1}"                           # 0 = install without opening the app
SECTIONS="${MAC_SETUP_SECTIONS:-}"              # MacBar sections, comma separated; empty = ask

ALL=(job-search macbar)

# ----------------------------------------------------------------------------- output

bold() { print -- "\033[1m$*\033[0m" }
info() { print -- "\033[34m==>\033[0m $*" }
ok()   { print -- "\033[32m  ✓\033[0m $*" }
step() { print -- "\033[2m  + $*\033[0m" }
warn() { print -u2 -- "\033[33mwarning:\033[0m $*" }
die()  { print -u2 -- "\033[31merror:\033[0m $*"; exit 1 }

# run <command...> — execute, or just show it under --dry-run.
#
# A failure here aborts the tool being installed. The check is explicit rather
# than left to `set -e`, because zsh suppresses errexit inside the `if` that
# runs each tool below, and a half-built bundle must not reach /Applications.
run() {
  if [ "$DRY_RUN" = 1 ]; then step "$*"; return 0; fi
  "$@" || die "command failed: $*"
}

# Same, for commands whose failure the caller handles itself.
run_ok() {
  if [ "$DRY_RUN" = 1 ]; then step "$*"; return 0; fi
  "$@"
}

# ask_yes <question> <y|n> — a yes/no question on the terminal; Return takes the
# default. End of input counts as Return.
ask_yes() {
  local question="$1" default="$2" hint=y/N answer
  [ "$default" = y ] && hint=Y/n
  while true; do
    print -n -- "$question [$hint] "
    read -r answer || { print; answer=""; }
    case "${answer:l}" in
      "")    [ "$default" = y ]; return ;;
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     print -- "  Please answer y or n." ;;
    esac
  done
}

# -------------------------------------------------------------------------- preflight

have() { command -v "$1" >/dev/null 2>&1 }

require_macos() { [ "$(uname)" = Darwin ] || die "this installer targets macOS" }
require_git()   { have git || die "git is required — install the Xcode Command Line Tools: xcode-select --install" }

# swiftc and codesign, both shipped by the Command Line Tools.
require_build_tools() {
  if ! have swiftc || ! have codesign; then
    die "swiftc and codesign are required — install them with: xcode-select --install"
  fi
}

# -------------------------------------------------------------------------- checkouts

# github.com/owner/repo, whatever form the remote takes.
normalize_remote() {
  local r="${1%.git}"
  r="${r#ssh://}"; r="${r#https://}"; r="${r#http://}"; r="${r#git@}"
  r="${r//://}"
  print -- "${r:l}"
}

# ensure_checkout <url> <preferred-dir-name> [alternate-dir-name...]
#
# Reuses an existing checkout of the same repository under any of the given
# names before cloning a fresh one. The result lands in $CHECKOUT.
ensure_checkout() {
  local url="$1" primary="$2"; shift 2
  local name dir remote

  for name in "$primary" "$@"; do
    dir="$SRC_DIR/$name"
    still_there "$dir" && [ -d "$dir/.git" ] || continue
    remote="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    if [ "$(normalize_remote "$remote")" = "$(normalize_remote "$url")" ]; then
      info "Using existing checkout: $dir"
      # Running the installer again is an update.
      run_ok git -C "$dir" pull --ff-only || warn "could not fast-forward $dir — leaving it as it is"
      CHECKOUT="$dir"
      return 0
    fi
  done

  dir="$SRC_DIR/$primary"
  still_there "$dir" && die "$dir already exists and is not a checkout of $url"
  info "Cloning $url"
  run mkdir -p "$SRC_DIR"
  run git clone "$url" "$dir"
  CHECKOUT="$dir"
}

# Move into the checkout. Under --dry-run the clone above did not really happen,
# so a missing directory is expected there and only there.
enter_checkout() {
  cd "$CHECKOUT" 2>/dev/null && return 0
  [ "$DRY_RUN" = 1 ] || die "cannot enter $CHECKOUT"
}

# ------------------------------------------------------------------------ fresh start

# What fresh_start moved to the Trash — or, under --dry-run, only said it would.
TRASHED=()

# still_there <path> — exists, and was not moved to the Trash. The second half
# only matters under --dry-run, where nothing really moved and the later steps
# have to be told so to show what a real run would do.
still_there() { [ -e "$1" ] && ! (( ${TRASHED[(Ie)${1:A}]} )) }

# to_trash <path...> — moves them to the Trash, from where Finder can put them
# back. macOS 15 and later have a trash command; before that the Trash is
# ~/.Trash, and a timestamp keeps a name from colliding with what is in it.
# Returns non-zero if anything could not be moved.
to_trash() {
  local p stamp
  if [ "$DRY_RUN" = 1 ]; then
    for p in "$@"; do step "move to the Trash: $p"; done
    return 0
  fi
  if have trash; then
    trash "$@"
    return
  fi
  stamp="$(date '+%Y-%m-%d %H.%M.%S')"
  mkdir -p "$HOME/.Trash" || return 1
  for p in "$@"; do
    mv "$p" "$HOME/.Trash/${p:t} $stamp" || return 1
  done
}

# --fresh: the install starts from fresh clones, and whatever the checkout
# folder holds goes to the Trash first. Two things survive:
#
#   - the checkout this script is running from, which the build needs;
#   - job-search's personal files — profile, config, reports, logs: whatever
#     git ignores there — copied into a fresh clone that takes the old one's
#     place, so that its scheduled agent, which runs from that path, carries on.
#
# The fresh job-search clone is made before anything moves, so a failure there
# leaves the folder as it was.
fresh_start() {
  local src="${SRC_DIR:A}" here="$SCRIPT_DIR" entry name keep="" js="" staging=""
  local -a entries doomed carried

  [ "$FRESH" = 1 ] || return 0
  entries=("$src"/*(DN))

  if [ -f "$here/menubar/Support.swift" ] && [[ "$here" == "$src"/* ]]; then
    keep="$src/${${here#$src/}%%/*}"
  fi
  for entry in $entries; do
    [ "$entry" = "$keep" ] || doomed+=("$entry")
  done
  [ ${#doomed} -gt 0 ] || return 0

  info "Starting from fresh checkouts: what is in $src goes to the Trash"
  [ -z "$keep" ] || print -- "  Keeping ${keep:t}, which this installer is running from"

  # job-search's checkout, under the names ensure_checkout would reuse.
  for name in ${=SECTION_DIRS[job-search]}; do
    entry="$src/$name"
    [ -d "$entry/.git" ] || continue
    if [ "$(normalize_remote "$(git -C "$entry" remote get-url origin 2>/dev/null || true)")" = "$(normalize_remote "$SECTION_REPO[job-search]")" ]; then
      js="$entry"
      break
    fi
  done

  if [ -n "$js" ]; then
    # Moving the folder out from under a run would leave it writing into the Trash.
    [ ! -d "$js/.run.lock" ] || die "a job search is running from $js — install again once it has finished, or remove $js/.run.lock if no search is running"
    carried=(${(f)"$(git -C "$js" ls-files --others --ignored --exclude-standard --directory)"})

    # Beside the folder, so that moving the clone in is a rename.
    if [ "$DRY_RUN" = 1 ]; then
      staging="${src:h}/.${src:t}.fresh"
    else
      staging="$(mktemp -d "${src:h}/.${src:t}.fresh.XXXXXX")" || die "could not make a folder for the fresh job-search clone — nothing was moved to the Trash"
    fi
    info "Cloning a fresh job-search to carry your files into"
    if ! run_ok git clone -q "$SECTION_REPO[job-search]" "$staging/${js:t}"; then
      rm -rf "$staging"
      die "could not clone job-search — nothing was moved to the Trash"
    fi
    for entry in $carried; do
      case "$entry" in .DS_Store|*/.DS_Store|.run.lock/) continue ;; esac
      if ! run_ok ditto "$js/$entry" "$staging/${js:t}/$entry"; then
        rm -rf "$staging"
        die "could not copy $entry out of $js — nothing was moved to the Trash"
      fi
      ok "Carrying over ${entry%/}"
    done
  fi

  to_trash $doomed || die "could not move everything in $src to the Trash${staging:+ — the fresh job-search, with your files, is in $staging}"
  ok "Moved ${#doomed} item(s) to the Trash"
  # job-search's path is about to hold the fresh clone.
  TRASHED=(${doomed:#${(b)js}})

  if [ -n "$js" ]; then
    run mv "$staging/${js:t}" "$js"
    run rmdir "$staging"
    ok "Fresh job-search in $js, with your files in it"
  fi
  print
}

# ----------------------------------------------------------------------- app installs

# install_bundle <path-to-.app> <process-name>
#
# Stops the running copy, then installs into /Applications when it is writable
# and ~/Applications otherwise. No sudo. The destination lands in $INSTALLED_APP.
install_bundle() {
  local src="$1" proc="$2"
  local base="/Applications"
  [ -w "$base" ] || base="$HOME/Applications"
  local dest="$base/${src:t}"

  run_ok pkill -x "$proc" 2>/dev/null || true
  run mkdir -p "$base"
  run rm -rf "$dest"
  run ditto "$src" "$dest"
  ok "Installed $dest"
  INSTALLED_APP="$dest"
}

launch_app() {
  [ "$LAUNCH" = 1 ] || return 0
  run open "$1"
  ok "Launched ${1:t:r} — look for it in the menu bar"
}

# add_login_item <path-to-.app> — opt in with --login-items.
add_login_item() {
  [ "$LOGIN_ITEMS" = 1 ] || return 0
  local app="$1" name="${1:t:r}"
  if [ "$DRY_RUN" = 1 ]; then step "register $app as a login item"; return 0; fi
  if osascript -e "tell application \"System Events\" to if not (exists login item \"$name\") then make login item at end with properties {path:\"$app\", hidden:false}" >/dev/null 2>&1; then
    ok "Added $name to your login items"
  else
    warn "could not add $name as a login item — add it by hand in System Settings > General > Login Items & Extensions"
  fi
}

# remove_legacy_login_items <app-name...> — drops the old apps' login items in
# one pass. Asking System Events whether an item exists is itself enough to raise
# the automation prompt, so this is only called once something has actually been
# retired.
remove_legacy_login_items() {
  local name script=""
  for name in "$@"; do
    script+="if exists login item \"$name\" then delete login item \"$name\"$'\n'"
  done
  if [ "$DRY_RUN" = 1 ]; then step "remove the $* login items, if there are any"; return 0; fi
  osascript -e "tell application \"System Events\"" -e "$script" -e "end tell" >/dev/null 2>&1 || true
}

# Three separate menu bar apps are now sections of MacBar. Leaving one installed
# alongside its section would put its item back in the menu bar at the next
# login, which is the thing being fixed. An app whose section was left out is
# left alone: it is still the only place that reading shows.
retire_legacy_bars() {
  local key name app plist running retired=0 label=com.jobsearch.menubar
  local -a legacy strays

  for key in $WANTED; do
    [ -z "$SECTION_LEGACY[$key]" ] || legacy+=("$SECTION_LEGACY[$key]")
  done

  # job-search launches its indicator from a launchd agent of its own — one its
  # setup may have just installed, which is why MacBar goes last.
  plist="$HOME/Library/LaunchAgents/$label.plist"
  if wants_section job-search && [ -f "$plist" ]; then
    run_ok launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    run rm -f "$plist"
    retired=1
    ok "Removed the job-search menu bar agent"
  fi

  for name in $legacy; do
    # Note where a running copy is launched from before stopping it: the two
    # menu bar apps used to be run straight out of their own checkouts, and a
    # bundle there is not this installer's to delete.
    running="$(pgrep -x "$name" >/dev/null 2>&1 && ps -o comm= -p "$(pgrep -x "$name" | head -1)" || true)"
    if [ -n "$running" ]; then
      retired=1
      run_ok pkill -x "$name" 2>/dev/null || true
      ok "Stopped $name"
      case "$running" in
        /Applications/*|"$HOME"/Applications/*) ;;
        *) strays+=("${running%/Contents/MacOS/*}") ;;
      esac
    fi

    for app in "/Applications/$name.app" "$HOME/Applications/$name.app"; do
      [ -d "$app" ] || continue
      run rm -rf "$app"
      retired=1
      ok "Removed $app"
    done
  done

  [ "$retired" = 1 ] || return 0
  remove_legacy_login_items $legacy
  info "Those apps are sections of MacBar now"
  for app in $strays; do
    print -- "  $app was running from its own checkout — delete it when you are sure MacBar covers it"
  done
  return 0
}

# ------------------------------------------------------------------------- the tools

# This repository holds the host: the status item, the dropdown, and the contract
# in menubar/Support.swift. Either it is already next to this script, or it comes
# from a checkout of mac-setup — which is what happens when the script is run
# straight off the network. The result lands in $CHECKOUT.
macbar_host() {
  local here="$SCRIPT_DIR"
  if [ -f "$here/menubar/Support.swift" ]; then
    info "Using the host next to this script: $here/menubar"
    CHECKOUT="$here"
    return 0
  fi
  ensure_checkout https://github.com/ainahtokyandry/mac-setup.git mac-setup
}

# Each section is a repository of its own, one row each, in the order they are
# offered:
#
#   key | name | what it shows | the type its file declares | repository |
#   checkout names, preferred first | the app it replaced, if any
#
# The type is how build.sh is told to leave a section out; the old app is what
# choosing the section retires.
SECTION_TABLE=(
  "storage|Storage|free space on the boot volume|StorageSection|https://github.com/ainahtokyandry/storage-bar.git|StorageBar storage-bar|StorageBar"
  "claude-usage|Claude usage|the three Claude usage limits|ClaudeUsageSection|https://github.com/ainahtokyandry/claude-usage.git|claude-usage|ClaudeUsageBar"
  "meetings|Meetings|today's meetings; needs calendar access|MeetingsSection|https://github.com/ainahtokyandry/meetings-bar.git|meetings-bar|"
  "job-search|Job search|the next scheduled job search run|JobSearchSection|https://github.com/ainahtokyandry/job-search.git|job-search|JobSearchBar"
)

typeset -a SECTION_KEYS
typeset -A SECTION_NAME SECTION_ABOUT SECTION_TYPE SECTION_REPO SECTION_DIRS SECTION_LEGACY

load_sections() {
  local row
  local -a col
  for row in $SECTION_TABLE; do
    col=("${(@s:|:)row}")
    SECTION_KEYS+=("$col[1]")
    SECTION_NAME[$col[1]]="$col[2]"
    SECTION_ABOUT[$col[1]]="$col[3]"
    SECTION_TYPE[$col[1]]="$col[4]"
    SECTION_REPO[$col[1]]="$col[5]"
    SECTION_DIRS[$col[1]]="$col[6]"
    SECTION_LEGACY[$col[1]]="$col[7]"
  done
}
load_sections

# The keys of the sections MacBar is built with, and of the ones left out, in
# table order. Settled by choose_sections before any tool runs.
WANTED=()
SKIPPED=()

wants_section() { (( ${WANTED[(Ie)$1]} )) }

# section_names <key...> — their display names, comma separated.
section_names() {
  local key
  local -a names
  for key in "$@"; do names+=("$SECTION_NAME[$key]"); done
  print -- "${(j:, :)names}"
}

# Settles WANTED and SKIPPED. --sections decides when it was given. Otherwise
# there is one question per section, each defaulting to what the last install
# chose, so that a rebuild does not quietly bring back a section that was left
# out; with no terminal to ask in, the last install's choice stands as it is.
choose_sections() {
  local key default
  local -a picked declined

  if [ -n "$SECTIONS" ]; then
    for key in ${(s:,:)${SECTIONS// /,}}; do
      key="${key:l}"
      if [ "$key" = all ]; then picked+=($SECTION_KEYS); continue; fi
      (( ${SECTION_KEYS[(Ie)$key]} )) || die "unknown section: $key (choose from ${(j:, :)SECTION_KEYS}, or all)"
      picked+=("$key")
    done
  else
    declined=($(defaults read local.macbar skippedSections 2>/dev/null || true))
    if [ -t 0 ]; then
      info "Which sections should MacBar have? Return keeps the answer in capitals."
      for key in $SECTION_KEYS; do
        default=y
        (( ${declined[(Ie)$key]} )) && default=n
        if ask_yes "$(printf '  %-13s %-40s' "$SECTION_NAME[$key]" "$SECTION_ABOUT[$key]")" $default; then
          picked+=("$key")
        fi
      done
    else
      for key in $SECTION_KEYS; do
        (( ${declined[(Ie)$key]} )) || picked+=("$key")
      done
      print -- "No terminal to ask which MacBar sections to include, so it gets the ones the last install chose, or all of them the first time. Choose with --sections."
    fi
  fi

  [ ${#picked} -gt 0 ] || die "no MacBar sections chosen — it needs at least one"
  for key in $SECTION_KEYS; do
    if (( ${picked[(Ie)$key]} )); then WANTED+=("$key"); else SKIPPED+=("$key"); fi
  done
  print -- "MacBar sections: $(section_names $WANTED)"
  [ ${#SKIPPED} -eq 0 ] || print -- "Left out:        $(section_names $SKIPPED)"
}

# Clones the chosen sections, and only those. They are cloned here rather than
# by the build so that a fresh Mac ends up with each of them, and so that an
# update brings them up to date.
ensure_sections() {
  local key
  for key in $WANTED; do
    # In a subshell, so that a section which cannot be prepared — no network, a
    # name already taken by something else — is left out of the build instead of
    # stopping it. MacBar is happy with whichever sections it finds.
    if ! ( ensure_checkout "$SECTION_REPO[$key]" ${=SECTION_DIRS[$key]} ); then
      warn "could not prepare the $SECTION_NAME[$key] section — MacBar will be built without it"
    fi
  done
  return 0
}

# Kept in MacBar's own preferences, so that the next install asks with the same
# answers as its defaults, and uses them as they are when it cannot ask.
remember_sections() {
  run defaults write local.macbar skippedSections -string "${SKIPPED[*]}"
}

# MacBar looks for the job-search checkout in JOBSEARCH_DIR, then in this
# preference, then in ~/Projects/job-search. Recording the path covers a
# checkout that sits anywhere else; without one the section stays hidden.
point_at_job_search() {
  wants_section job-search || return 0
  local dir found=""
  for dir in "$SRC_DIR"/*(N/); do
    if [ -f "$dir/run-search.sh" ] && [ -f "$dir/prompt-template.md" ]; then found="$dir"; break; fi
  done
  [ -n "$found" ] || return 0
  run defaults write local.macbar jobSearchDir "$found"
  ok "MacBar will read the job search from $found"
}

# Nothing ships a prebuilt binary, so the bundle is assembled by
# menubar/build.sh: the host from this repository, plus every section it finds
# under $SRC_DIR except the ones left out. Its ad hoc codesign step is not
# optional — an unsigned bundle will not launch on recent versions of macOS.
install_macbar() {
  local key
  local -a skip_types
  bold "MacBar — one menu bar item, one section per tool"
  require_git
  require_build_tools

  # Not needed to build, but the usage section has no sign-in of its own: it
  # reads the OAuth token Claude Code keeps in the login keychain.
  have claude || warn "Claude Code was not found on this Mac. MacBar reads the token it stores in the login keychain, so the usage section will say 'Not signed in' until you install the CLI and run 'claude auth login'."

  macbar_host
  local host="$CHECKOUT"
  ensure_sections

  cd "$host" 2>/dev/null || [ "$DRY_RUN" = 1 ] || die "cannot enter $host"
  [ "$DRY_RUN" = 1 ] || [ -f menubar/Support.swift ] || die "menubar/Support.swift is missing from $host"

  # A section left out is named to build.sh as well as not cloned: its repository
  # may be checked out for another reason — job-search is a tool as well as a
  # section — and build.sh takes every section it finds. A section that is not
  # in the table, one written for this Mac alone, still goes in.
  for key in $SKIPPED; do skip_types+=("$SECTION_TYPE[$key]"); done

  info "Building MacBar.app from the host and every section under $SRC_DIR, less any left out"
  # MACBAR_SRC_DIR is where build.sh looks for sections.
  run env MACBAR_SRC_DIR="$SRC_DIR" MACBAR_SKIP="${(j.:.)skip_types}" ./menubar/build.sh "$host/menubar/MacBar.app"

  retire_legacy_bars
  install_bundle "$host/menubar/MacBar.app" MacBar
  remember_sections
  point_at_job_search
  add_login_item "$INSTALLED_APP"
  launch_app "$INSTALLED_APP"
  print -- "If macOS asks for permission to read 'Claude Code-credentials' from your keychain, choose Always Allow."
  if wants_section meetings; then
    print -- "If it asks for access to your calendars and to send notifications, allow both: the meetings section lists today's meetings and reminds you before each one."
  fi
}

# job-search carries its own interactive installer, which asks about the
# schedule, the profile, the launchd agent and the menu bar indicator.
install_job_search() {
  bold "job-search — a scheduled agent that sweeps job boards for you"
  require_git

  have claude || warn "Claude Code was not found on this Mac. job-search shells out to the 'claude' CLI, so runs will fail until it is installed and signed in: https://claude.com/claude-code"

  ensure_checkout https://github.com/ainahtokyandry/job-search.git job-search
  enter_checkout

  if [ "$DRY_RUN" = 1 ]; then
    step "$CHECKOUT/setup.sh (interactive)"
    return 0
  fi

  if [ ! -t 0 ]; then
    warn "setup.sh asks four questions and needs a terminal. Finish the install with:"
    print -- "    cd $CHECKOUT && ./setup.sh"
    return 0
  fi

  # Its fourth question can build the standalone indicator, which needs the host
  # this repository holds. Pointing at it means the offer works even when
  # mac-setup was cloned somewhere unusual.
  if [ -f "$SCRIPT_DIR/menubar/Support.swift" ]; then
    export MACBAR_HOST="$SCRIPT_DIR/menubar"
  fi

  info "Handing over to setup.sh — every question has a default you can accept with Return"
  if installing_macbar; then
    if wants_section job-search; then
      print -- "Question 4 offers a menu bar indicator of its own; 'n' is the default, and the right answer here — MacBar has a job search section."
    else
      print -- "Question 4 offers a menu bar indicator of its own. MacBar is being built without its job search section, so answer 'y' if you want the job search in the menu bar."
    fi
  fi
  ./setup.sh || die "setup.sh failed in $CHECKOUT"
  ok "job-search is set up in $CHECKOUT"
  print -- "Run one search now with:  cd $CHECKOUT && ./run-search.sh --force"
}

# ------------------------------------------------------------------------------- main

usage() {
  cat <<EOF
Usage: install.sh [options] [tool ...]

Tools (default: both, job-search first)
  job-search         a scheduled agent that sweeps job boards
  macbar             one menu bar item, assembled from this repository's host
                     and the sections you choose

  storage-bar and claude-usage are accepted as older names for macbar. They are
  sections of it now, not apps of their own.

MacBar sections (default: ask, one question each)
  storage            free space on the boot volume
  claude-usage       the three Claude usage limits
  meetings           today's meetings, and a reminder before each
  job-search         the next scheduled job search run

  A section left out is not cloned for MacBar and not built in, and the app it
  replaced is left alone. The choice is remembered: the next install asks with
  the same answers as its defaults, and uses them as they are when there is no
  terminal to ask in. A section found in \$HOME/MacBar that is not one of
  these goes in as well.

Options
  -s, --sections LIST
                     MacBar sections to include, comma separated, or all —
                     answers the questions up front
  -f, --fresh        empty \$HOME/MacBar into the Trash first, and start from
                     fresh clones
  -l, --login-items  register MacBar to open at login
  -N, --no-launch    install without opening the app
  -n, --dry-run      print the commands instead of running them
  -h, --help         this text

Checkouts live in \$HOME/MacBar, and running the installer again is an update.
Each checkout there is fast-forwarded, a section newly chosen is cloned, and
MacBar is rebuilt around them; files of your own in those checkouts stay where
they are. A checkout that cannot be fast-forwarded — no network, or local
changes in the way — is built as it stands, with a warning.

An existing checkout is reused when it sits in its usual folder: StorageBar or
storage-bar, claude-usage, meetings-bar, job-search. One in a folder by any
other name is not looked for, so a second copy is cloned beside it, and if
MacBar includes that section the build stops on the duplicate; rename the
folder first.

--fresh starts over instead: what \$HOME/MacBar holds goes to the Trash first.
The exceptions are the mac-setup checkout the installer is running from, if it
is in there, and job-search's personal files (profile, config, reports, logs),
which are copied into a fresh clone at the same path. While a job search is
running the install stops instead, with nothing moved. Nothing needs sudo.

A section repository that cannot be cloned is simply left out of the build.

Installing macbar retires the apps its sections replaced — StorageBar.app,
ClaudeUsageBar.app and JobSearchBar.app, with job-search's menu bar launchd
agent — each one only when its section is included.
EOF
}

targets=()
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--sections)    [ $# -ge 2 ] || die "--sections needs a list, such as storage,meetings"; SECTIONS="$2"; shift 2 ;;
    -f|--fresh)       FRESH=1; shift ;;
    -l|--login-items) LOGIN_ITEMS=1; shift ;;
    -N|--no-launch)   LAUNCH=0; shift ;;
    -n|--dry-run)     DRY_RUN=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    -*)               die "unknown option: $1 (try --help)" ;;
    macbar|menubar)   targets+=(macbar); shift ;;
    storage-bar|claude-usage)
                      warn "$1 is a section of MacBar now — installing macbar instead"
                      targets+=(macbar); shift ;;
    job-search)       targets+=(job-search); shift ;;
    *)                die "unknown tool: $1 (try --help)" ;;
  esac
done

[ ${#targets} -gt 0 ] || targets=($ALL)
# Both old names map to macbar, so a repeat is easy to ask for by accident.
targets=(${(u)targets})
# MacBar goes last whatever order was asked for: it retires the old menu bar
# apps, and job-search's own setup can put one of them back.
targets=(${targets:#macbar} ${(M)targets:#macbar})

installing_macbar() { [[ " ${targets[*]} " == *" macbar "* ]] }

require_macos

bold "Installing: ${targets[*]}"
print -- "Checkouts go in $SRC_DIR"
[ "$DRY_RUN" = 1 ] && print -- "Dry run — nothing will be changed"
print

# Asked before anything runs, so that job-search's setup can be told whether
# MacBar will have a job search section.
if installing_macbar; then
  choose_sections
  print
elif [ -n "$SECTIONS" ]; then
  warn "--sections only applies to macbar — ignoring it"
fi

# Only with --fresh. After the questions, so that answering them can still be
# abandoned with nothing moved; before any tool, so that every one of them
# clones afresh.
fresh_start

failed=()
for tool in $targets; do
  # A subshell per tool: one failure cannot leave a stray cd or abort the rest.
  if ( install_${tool//-/_} ); then :; else
    warn "$tool failed"
    failed+=("$tool")
  fi
  print
done

[ ${#failed} -gt 0 ] && die "failed: ${failed[*]}"
bold "Done."
