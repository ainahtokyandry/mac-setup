#!/bin/zsh
# Installs my personal macOS tools, from one file with no dependencies of its own:
#
#   storage-bar    https://github.com/ainahtokyandry/storage-bar
#   claude-usage   https://github.com/ainahtokyandry/claude-usage
#   job-search     https://github.com/ainahtokyandry/job-search
#
# Locally:
#   ./install.sh                  install all three
#   ./install.sh storage-bar      install one
#   ./install.sh --dry-run        print the commands instead of running them
#
# Straight off the network, without cloning anything first:
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/ainahtokyandry/mac-setup/main/install.sh)"
#
# Use that form rather than `curl … | zsh`: a pipe occupies stdin, and
# job-search's setup asks questions that need the terminal. Arguments go after
# the command string, past a placeholder that lands in $0:
#   zsh -c "$(curl -fsSL …/install.sh)" install --dry-run storage-bar

set -euo pipefail

# --------------------------------------------------------------------------- settings

SRC_DIR="${MAC_SETUP_SRC_DIR:-$HOME/Projects}"  # where checkouts live
DRY_RUN="${DRY_RUN:-0}"                         # 1 = print commands, change nothing
UPDATE="${UPDATE:-0}"                           # 1 = git pull --ff-only in existing checkouts
LOGIN_ITEMS="${LOGIN_ITEMS:-0}"                 # 1 = register the apps to open at login
LAUNCH="${LAUNCH:-1}"                           # 0 = install without opening the apps

ALL=(storage-bar claude-usage job-search)

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

# ------------------------------------------------------------------------- the tools

# Both menu bar apps ship source rather than a prebuilt binary, so the bundle is
# assembled here. The ad hoc codesign step is not optional: an unsigned bundle
# will not launch on recent versions of macOS.

install_storage_bar() {
  bold "StorageBar — free disk space in the menu bar"
  require_git
  require_build_tools

  ensure_checkout https://github.com/ainahtokyandry/storage-bar.git StorageBar storage-bar
  enter_checkout
  [ "$DRY_RUN" = 1 ] || [ -f main.swift ] || die "main.swift is missing from $CHECKOUT"

  info "Building StorageBar.app"
  run mkdir -p StorageBar.app/Contents/MacOS
  run cp Info.plist StorageBar.app/Contents/Info.plist
  run swiftc -O main.swift -o StorageBar.app/Contents/MacOS/StorageBar
  run codesign --force --sign - StorageBar.app
  ok "Built $CHECKOUT/StorageBar.app"

  install_bundle "$CHECKOUT/StorageBar.app" StorageBar
  add_login_item "$INSTALLED_APP"
  launch_app "$INSTALLED_APP"
}

install_claude_usage() {
  bold "ClaudeUsageBar — your three Claude usage limits in the menu bar"
  require_git
  require_build_tools

  # Not needed to build, but the app has no sign-in of its own: it reads the
  # OAuth token Claude Code keeps in the login keychain.
  have claude || warn "Claude Code was not found on this Mac. ClaudeUsageBar reads the token it stores in the login keychain, so the menu bar will show 'Not signed in' until you install the CLI and run 'claude auth login'."

  ensure_checkout https://github.com/ainahtokyandry/claude-usage.git claude-usage
  enter_checkout

  info "Building ClaudeUsageBar.app"
  if [ "$DRY_RUN" != 1 ] && [ -x ./build.sh ]; then
    ./build.sh || die "build.sh failed in $CHECKOUT"
  else
    # Same steps as build.sh, for a checkout that predates it.
    run mkdir -p ClaudeUsageBar.app/Contents/MacOS
    run cp Info.plist ClaudeUsageBar.app/Contents/Info.plist
    run swiftc -O main.swift -o ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar
    run codesign --force --sign - ClaudeUsageBar.app
  fi
  ok "Built $CHECKOUT/ClaudeUsageBar.app"

  install_bundle "$CHECKOUT/ClaudeUsageBar.app" ClaudeUsageBar
  add_login_item "$INSTALLED_APP"
  launch_app "$INSTALLED_APP"
  print -- "If macOS asks for permission to read 'Claude Code-credentials' from your keychain, choose Always Allow."
}

# job-search carries its own interactive installer, which asks about the
# schedule, the profile, the launchd agent and the menu bar indicator.
install_job_search() {
  bold "job-search — a scheduled agent that sweeps job boards for you"
  require_git

  have claude || warn "Claude Code was not found on this Mac. job-search shells out to the 'claude' CLI, so runs will fail until it is installed and signed in: https://claude.com/claude-code"
  if ! have swiftc || ! have codesign; then
    warn "swiftc/codesign are missing, so the optional menu bar indicator cannot be built. Install them with: xcode-select --install"
  fi

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

  info "Handing over to setup.sh — every question has a default you can accept with Return"
  ./setup.sh || die "setup.sh failed in $CHECKOUT"
  ok "job-search is set up in $CHECKOUT"
  print -- "Run one search now with:  cd $CHECKOUT && ./run-search.sh --force"
}

# ------------------------------------------------------------------------------- main

usage() {
  cat <<EOF
Usage: install.sh [options] [tool ...]

Tools (default: all of them, in this order)
  storage-bar        free disk space in the menu bar
  claude-usage       the three Claude usage limits in the menu bar
  job-search         a scheduled agent that sweeps job boards

Options
  -d, --dir DIR      where checkouts live (default: \$HOME/Projects)
  -u, --update       fast-forward existing checkouts before building
  -l, --login-items  register the menu bar apps to open at login
  -N, --no-launch    install without opening the apps
  -n, --dry-run      print the commands instead of running them
  -h, --help         this text

An existing checkout of a repository is reused wherever it already sits under
DIR, whatever the folder is called; nothing is re-cloned, and nothing is pulled
unless --update is given. Nothing needs sudo.
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
    storage-bar|claude-usage|job-search) targets+=("$1"); shift ;;
    *)                die "unknown tool: $1 (try --help)" ;;
  esac
done

[ ${#targets} -gt 0 ] || targets=($ALL)

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
