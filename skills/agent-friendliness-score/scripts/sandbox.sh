#!/usr/bin/env bash
# Manages the throwaway clone for agent-friendliness-score. Run it from inside
# the scored repo. Paths live in a state file, so nothing depends on shell state
# surviving between commands, and every command that touches the clone checks
# first that the clone is what the state file says it is.
set -euo pipefail
umask 077
export GIT_OPTIONAL_LOCKS=0

base="${AFS_HOME:-$HOME/.agent-friendliness-score}"
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"
credential_names='TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|API_?KEY|ACCESS_KEY|PRIVATE_KEY|^AWS_|^AZURE_|^GOOGLE_APPLICATION|^KUBECONFIG$|^SSH_AUTH_SOCK$|_DSN$|(DATABASE|DB|REDIS|MONGO|AMQP|RABBIT|KAFKA)[A-Z_]*_URL$'

die() { echo "sandbox.sh: $*" >&2; exit 1; }
hash8() { git hash-object --stdin | cut -c1-8; }
slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9._]+/-/g; s/^-+//; s/-+$//'; }
credentials() { compgen -e | grep -E "$credential_names" | sort || true; }

scored_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "run this from inside the scored repo"
}

# The same repo gets the same id over HTTPS or SSH, and credentials in the URL
# never reach the id. A repo with no remote falls back to its root commit.
repo_id() {
  local root remote url
  root=$(scored_root)
  remote=$(git remote | grep -x origin || git remote | head -1 || true)
  if [ -n "$remote" ]; then
    url=$(git remote get-url "$remote" | tr 'A-Z' 'a-z' | sed -E \
      -e 's#^[a-z+]+://##' -e 's#^[^/@]*@##' -e 's#^([^/:]+):[0-9]+/#\1/#' \
      -e 's#^([^/:]+):#\1/#' -e 's#/+$##' -e 's#\.git$##')
    printf '%s-%s' "$(slug "${url##*/}")" "$(printf '%s' "$url" | hash8)"
  else
    printf '%s-%s' "$(slug "$(basename "$root")")" \
      "$(git rev-list --max-parents=0 HEAD | tail -1 | cut -c1-8)"
  fi
}

snapshot() {
  local hooks
  hooks=$(git -C "$1" rev-parse --git-path hooks)
  case "$hooks" in /*) ;; *) hooks="$1/$hooks" ;; esac
  echo "== status"; git -C "$1" status --porcelain=v1
  echo "== head"; git -C "$1" rev-parse HEAD
  echo "== refs"; git -C "$1" for-each-ref
  echo "== stash"; git -C "$1" stash list
  echo "== worktrees"; git -C "$1" worktree list --porcelain
  echo "== config hash"; git -C "$1" config --local --list | hash8
  echo "== hooks"; ls -A "$hooks" 2>/dev/null || true
}

orphans() {
  local dir state known
  for dir in "$tmp_root"/afs-sandbox.*; do
    [ -d "$dir" ] || continue
    known=no
    for state in "$base"/.active/*.env; do
      [ -f "$state" ] && grep -qF "$dir" "$state" && known=yes
    done
    [ "$known" = no ] && echo "leftover_clone=$dir"
  done
  return 0
}

load_state() {
  state_file="$base/.active/$(repo_id).env"
  [ -f "$state_file" ] || die "no active run for this repo. Run setup from the scored repo."
  # shellcheck disable=SC1090
  . "$state_file"
}

guard() {
  load_state
  [ -n "${sandbox:-}" ] && [ -n "${scored_repo:-}" ] && [ -n "${commit:-}" ] \
    || die "state file $state_file is incomplete"
  [ "$(scored_root)" = "$scored_repo" ] || die "run this from the scored repo, $scored_repo"
  [ "$sandbox" != "$scored_repo" ] || die "the clone path is the scored repo. Refusing."
  [ "$(git -C "$sandbox" rev-parse --show-toplevel 2>/dev/null)" = "$sandbox" ] \
    || die "$sandbox is not its own git toplevel. Refusing."
  [ -z "$(git -C "$sandbox" remote)" ] || die "$sandbox has a remote, so it isn't the throwaway clone. Refusing."
}

sandbox_git() { git -C "$sandbox" -c core.hooksPath=/dev/null "$@"; }

in_save_dir() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *..*) die "bad relative path: $1" ;;
    *) printf '%s/%s' "$save_dir" "$1" ;;
  esac
}

cmd_preflight() {
  local blocked=0 root probe url
  command -v git >/dev/null || die "git is not installed"
  root=$(scored_root)
  if ! git rev-parse --verify -q HEAD >/dev/null; then
    echo "no_commits=true: this repo has no commits, so there's nothing to score."
    exit 3
  fi
  echo "repo_id=$(repo_id)"
  echo "shallow=$(git rev-parse --is-shallow-repository)"
  if probe=$(mktemp -d "$tmp_root/afs-probe.XXXXXX" 2>/dev/null); then
    rm -rf "$probe"; echo "temp_write=ok ($tmp_root)"
  else
    echo "temp_write=blocked ($tmp_root)"; blocked=1
  fi
  case "$base/" in
    "$root"/*) echo "save_write=blocked ($base is inside the scored repo)"; blocked=1 ;;
    /*)
      if mkdir -p "$base" 2>/dev/null && probe=$(mktemp "$base/.probe.XXXXXX" 2>/dev/null); then
        rm -f "$probe"; echo "save_write=ok ($base)"
      else
        echo "save_write=blocked ($base)"; blocked=1
      fi ;;
    *) echo "save_write=blocked (AFS_HOME must be an absolute path)"; blocked=1 ;;
  esac
  if ! command -v gh >/dev/null; then echo "gh=not installed"
  elif gh api rate_limit >/dev/null 2>&1; then echo "gh=ok"
  else echo "gh=unavailable (not logged in or no network)"; fi
  for url in "${@:-https://github.com}"; do
    if ! command -v curl >/dev/null; then echo "network=unknown, no curl ($url)"
    elif curl -sS -o /dev/null --max-time 8 -I "$url" 2>/dev/null; then echo "network=ok ($url)"
    else echo "network=blocked ($url)"; fi
  done
  echo "credentials_unset_for_test_runs=$(credentials | paste -sd, -)"
  [ ! -f "$base/.active/$(repo_id).env" ] \
    || echo "active_run=$base/.active/$(repo_id).env (run finish to clean it up, or it blocks setup)"
  orphans
  [ "$blocked" = 0 ] || exit 1
}

cmd_setup() {
  local scope="${1:-}" id root run_dir stamp dir
  root=$(scored_root)
  git rev-parse --verify -q HEAD >/dev/null \
    || { echo "This repo has no commits, so there's nothing to score." >&2; exit 3; }
  id=$(repo_id)
  state_file="$base/.active/$id.env"
  [ ! -f "$state_file" ] || die "a run is already active or crashed: $state_file. Run finish first."
  commit=$(git rev-parse HEAD)
  run_dir="$base/$id${scope:+--$(slug "$scope")}"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  save_dir="$run_dir/$stamp"
  previous_run=""
  for dir in "$run_dir"/*/; do
    [ -f "${dir}complete" ] && previous_run="${dir%/}"
  done
  mkdir -p "$base/.active" "$save_dir/seeded" "$save_dir/violations" "$save_dir/context"
  chmod -R go-rwx "$base"

  parent=$(mktemp -d "$tmp_root/afs-sandbox.XXXXXX")
  parent=$(cd "$parent" && pwd -P)
  trap 'rm -rf "$parent"' EXIT
  sandbox="$parent/repo"
  git -c core.hooksPath=/dev/null clone --quiet --local --no-checkout --template= -- "$root" "$sandbox"
  # A detached HEAD in a linked worktree isn't copied by clone, so fetch it.
  git -C "$sandbox" cat-file -e "$commit^{commit}" 2>/dev/null \
    || git -C "$sandbox" -c core.hooksPath=/dev/null fetch --quiet "$root" "$commit"
  git -C "$sandbox" remote remove origin
  git -C "$sandbox" config core.hooksPath /dev/null
  git -C "$sandbox" -c core.hooksPath=/dev/null checkout --quiet --detach "$commit"
  snapshot "$root" > "$save_dir/scored-repo-before.txt"
  {
    printf 'sandbox=%q\n' "$sandbox"
    printf 'scored_repo=%q\n' "$root"
    printf 'commit=%q\n' "$commit"
    printf 'save_dir=%q\n' "$save_dir"
    printf 'previous_run=%q\n' "$previous_run"
  } > "$state_file"
  trap - EXIT
  cmd_paths
  [ ! -f "$root/.gitmodules" ] || echo "warning=submodules are not in the clone"
  grep -qs 'filter=lfs' "$root/.gitattributes" && echo "warning=Git LFS files may be pointers in the clone"
  [ "$(git rev-parse --is-shallow-repository)" = false ] \
    || echo "warning=shallow clone, so history-based checks are not measured"
  orphans
}

cmd_paths() {
  [ -n "${sandbox:-}" ] || load_state
  echo "sandbox=$sandbox"
  echo "commit=$commit"
  echo "save_dir=$save_dir"
  echo "previous_run=$previous_run"
}

cmd_run() {
  [ "${1:-}" = "--" ] && shift
  [ "$#" -gt 0 ] || die "usage: run -- <command>"
  guard
  local status=0 started=$SECONDS
  (
    cd "$sandbox"
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    for name in $(credentials); do unset "$name"; done
    exec "$@"
  ) || status=$?
  echo "exit=$status elapsed_seconds=$((SECONDS - started))" >&2
  return "$status"
}

cmd_apply() {
  [ "$#" = 1 ] || die "usage: apply <patch>"
  guard
  local patch
  patch=$(in_save_dir "$1")
  [ -f "$patch" ] || die "no such patch: $patch"
  sandbox_git apply --check "$patch"
  sandbox_git apply "$patch"
}

cmd_capture() {
  [ "$#" = 1 ] || die "usage: capture <path relative to the save folder>"
  guard
  local patch
  case "$1" in /*) die "capture takes a relative path" ;; esac
  patch=$(in_save_dir "$1")
  mkdir -p "$(dirname "$patch")"
  sandbox_git add -AN .
  sandbox_git diff --binary > "$patch"
  [ -s "$patch" ] || { rm -f "$patch"; die "the clone has no changes to capture"; }
  cmd_restore
}

cmd_restore() {
  guard
  sandbox_git reset --quiet --hard HEAD
  sandbox_git clean -fdq
  # Something in the run moved HEAD, for example a test that made a commit.
  [ "$(sandbox_git rev-parse HEAD)" = "$commit" ] \
    || sandbox_git checkout --quiet --force --detach "$commit"
  [ -z "$(sandbox_git status --porcelain)" ] \
    || die "the clone isn't clean after restoring: $(sandbox_git status --porcelain | head -5)"
}

cmd_finish() {
  local complete=no parent status=0
  [ "${1:-}" = "--complete" ] && complete=yes
  load_state
  if [ "$complete" = yes ]; then
    [ -f "$save_dir/report.md" ] && [ -f "$save_dir/result.json" ] \
      || die "save report.md and result.json in $save_dir before finishing with --complete"
  fi
  parent=$(dirname "$sandbox")
  case "$parent" in
    "$tmp_root"/afs-sandbox.*|*/afs-sandbox.*) ;;
    *) die "$parent doesn't look like a sandbox folder, so it wasn't removed" ;;
  esac
  if [ -e "$parent" ]; then
    chmod -R u+w "$parent" 2>/dev/null || true
    rm -rf "$parent" 2>/dev/null || true
  fi
  [ ! -e "$parent" ] || die "could not remove the clone. Remove it by hand: $parent"
  if [ "$(scored_root)" = "$scored_repo" ] && [ -f "$save_dir/scored-repo-before.txt" ]; then
    if ! snapshot "$scored_repo" | diff -U1 "$save_dir/scored-repo-before.txt" - > "$save_dir/scored-repo-diff.txt"; then
      echo "scored_repo=CHANGED since setup, see $save_dir/scored-repo-diff.txt (it may be your own work)" >&2
      status=4
    else
      rm -f "$save_dir/scored-repo-diff.txt"
      echo "scored_repo=unchanged"
    fi
  else
    echo "scored_repo=not checked, run finish from the scored repo" >&2
    status=4
  fi
  rm -f "$state_file"
  [ "$complete" = no ] || touch "$save_dir/complete"
  echo "clone_removed=$parent"
  echo "save_dir=$save_dir"
  exit "$status"
}

command="${1:-}"
[ "$#" = 0 ] || shift
case "$command" in
  preflight|setup|paths|run|apply|capture|restore|finish) "cmd_$command" "$@" ;;
  *) die "usage: sandbox.sh preflight|setup [scope]|paths|run -- <command>|apply <patch>|capture <path>|restore|finish [--complete]" ;;
esac
