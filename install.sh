#!/bin/zsh
# Installs my personal macOS tools:
#
#   macbar         one menu bar item for disk space, Claude usage and the job
#                  search — built from menubar/ in this repository
#   job-search     https://github.com/ainahtokyandry/job-search
#
# Locally:
#   ./install.sh                  install both
#   ./install.sh macbar           install one
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

SRC_DIR="${MAC_SETUP_SRC_DIR:-$HOME/Projects}"  # where checkouts live
DRY_RUN="${DRY_RUN:-0}"                         # 1 = print commands, change nothing
UPDATE="${UPDATE:-0}"                           # 1 = git pull --ff-only in existing checkouts
LOGIN_ITEMS="${LOGIN_ITEMS:-0}"                 # 1 = register the app to open at login
LAUNCH="${LAUNCH:-1}"                           # 0 = install without opening the app

ALL=(job-search macbar)

# The apps MacBar replaces, one section each.
LEGACY_BARS=(StorageBar ClaudeUsageBar JobSearchBar)

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
    [ -d "$dir/.git" ] || continue
    remote="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    if [ "$(normalize_remote "$remote")" = "$(normalize_remote "$url")" ]; then
      info "Using existing checkout: $dir"
      if [ "$UPDATE" = 1 ]; then
        run_ok git -C "$dir" pull --ff-only || warn "could not fast-forward $dir — leaving it as it is"
      fi
      CHECKOUT="$dir"
      return 0
    fi
  done

  dir="$SRC_DIR/$primary"
  [ -e "$dir" ] && die "$dir already exists and is not a checkout of $url"
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

# Drops the old apps' login items in one pass. Asking System Events whether an
# item exists is itself enough to raise the automation prompt, so this is only
# called once something has actually been retired.
remove_legacy_login_items() {
  local name script=""
  for name in $LEGACY_BARS; do
    script+="if exists login item \"$name\" then delete login item \"$name\"$'\n'"
  done
  if [ "$DRY_RUN" = 1 ]; then step "remove the ${LEGACY_BARS[*]} login items, if there are any"; return 0; fi
  osascript -e "tell application \"System Events\"" -e "$script" -e "end tell" >/dev/null 2>&1 || true
}

# The three separate menu bar apps are now sections of MacBar. Leaving them
# installed would put their items back in the menu bar at the next login, which
# is the thing being fixed.
retire_legacy_bars() {
  local name app plist running retired=0 label=com.jobsearch.menubar
  local -a strays

  # job-search launches its indicator from a launchd agent of its own.
  plist="$HOME/Library/LaunchAgents/$label.plist"
  if [ -f "$plist" ]; then
    run_ok launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    run rm -f "$plist"
    retired=1
    ok "Removed the job-search menu bar agent"
  fi

  for name in $LEGACY_BARS; do
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
  remove_legacy_login_items
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
  local here="${0:A:h}"
  if [ -f "$here/menubar/Support.swift" ]; then
    info "Using the host next to this script: $here/menubar"
    CHECKOUT="$here"
    return 0
  fi
  ensure_checkout https://github.com/ainahtokyandry/mac-setup.git mac-setup
}

# Each section is a repository of its own, and MacBar is built from whichever ones
# are on the machine. They are cloned here rather than by the build so that a
# fresh Mac ends up with all of them, and so --update refreshes them.
SECTION_REPOS=(
  "https://github.com/ainahtokyandry/storage-bar.git StorageBar storage-bar"
  "https://github.com/ainahtokyandry/claude-usage.git claude-usage"
  "https://github.com/ainahtokyandry/meetings-bar.git meetings-bar"
  "https://github.com/ainahtokyandry/job-search.git job-search"
)

ensure_sections() {
  local spec
  local -a parts
  for spec in $SECTION_REPOS; do
    parts=(${=spec})   # url, preferred directory name, then older names to reuse
    # In a subshell, so that a section which cannot be prepared — no network, a
    # name already taken by something else — is left out of the build instead of
    # stopping it. MacBar is happy with whichever sections it finds.
    if ! ( ensure_checkout $parts ); then
      warn "could not prepare ${parts[2]} — MacBar will be built without that section"
    fi
  done
  return 0
}

# MacBar looks for the job-search checkout in JOBSEARCH_DIR, then in this
# preference, then in ~/Projects/job-search. Recording the path covers a
# checkout that sits anywhere else; without one the section stays hidden.
point_at_job_search() {
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
# under $SRC_DIR. Its ad hoc codesign step is not optional — an unsigned bundle
# will not launch on recent versions of macOS.
install_macbar() {
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

  info "Building MacBar.app from the host and every section under $SRC_DIR"
  export MACBAR_SRC_DIR="$SRC_DIR"   # where build.sh looks for sections
  run ./menubar/build.sh "$host/menubar/MacBar.app"

  retire_legacy_bars
  install_bundle "$host/menubar/MacBar.app" MacBar
  point_at_job_search
  add_login_item "$INSTALLED_APP"
  launch_app "$INSTALLED_APP"
  print -- "If macOS asks for permission to read 'Claude Code-credentials' from your keychain, choose Always Allow."
  print -- "If it asks for access to your calendars and to send notifications, allow both: the meetings section lists today's meetings and reminds you before each one."
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
  if [ -f "${0:A:h}/menubar/Support.swift" ]; then
    export MACBAR_HOST="${0:A:h}/menubar"
  fi

  info "Handing over to setup.sh — every question has a default you can accept with Return"
  if installing_macbar; then
    print -- "Question 4 offers a menu bar indicator of its own; 'n' is the default, and the right answer here — MacBar has a job search section."
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
                     and every section repository found under DIR: disk space,
                     the Claude usage limits, today's meetings, and the job search

  storage-bar and claude-usage are accepted as older names for macbar. They are
  sections of it now, not apps of their own.

Options
  -d, --dir DIR      where checkouts live (default: \$HOME/Projects)
  -u, --update       fast-forward existing checkouts before building
  -l, --login-items  register MacBar to open at login
  -N, --no-launch    install without opening the app
  -n, --dry-run      print the commands instead of running them
  -h, --help         this text

An existing checkout of a repository is reused wherever it already sits under
DIR, whatever the folder is called; nothing is re-cloned, and nothing is pulled
unless --update is given. Nothing needs sudo.

Because each section is its own repository, editing one and re-running

    ./install.sh --update macbar

pulls every section and rebuilds the app around them. A section repository that
is not there is simply left out of the build.

Installing macbar retires StorageBar.app, ClaudeUsageBar.app and
JobSearchBar.app, along with job-search's menu bar launchd agent.
EOF
}

targets=()
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--dir)         [ $# -ge 2 ] || die "--dir needs a directory"; SRC_DIR="${2:A}"; shift 2 ;;
    -u|--update)      UPDATE=1; shift ;;
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
