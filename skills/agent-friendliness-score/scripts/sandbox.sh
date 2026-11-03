#!/usr/bin/env bash
# Manages the throwaway clone for agent-friendliness-score. Run it from inside
# the scored repo, by absolute path. Paths live in a state file, which is parsed
# rather than executed. Before it changes or removes the clone, the script checks
# that the recorded path has the shape setup creates, holds setup's marker file,
# and (except for finish, which may find it half removed) is its own git toplevel
# with no remote. These checks catch mistakes and a damaged state file. They
# don't defend against someone who can also forge the marker.
set -euo pipefail

# A hook or an agent's shell may export these, and they would point git at the
# wrong repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
export GIT_OPTIONAL_LOCKS=0
# Keep LFS pointers. The clone has no remote to fetch real files from.
export GIT_LFS_SKIP_SMUDGE=1

caller_umask=$(umask)
base="${AFS_HOME:-$HOME/.agent-friendliness-score}"
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"
parent=""
credential_names='TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|ASKPASS|API_?KEY|ACCESS_KEY|PRIVATE_KEY|_KEY$|_PAT$|_AUTH$|_DSN$|^PG|^AWS_|^AZURE_|^GOOGLE_APPLICATION|^KUBECONFIG$|^SSH_AUTH_SOCK$|(DATABASE|DB|POSTGRES|MYSQL|MARIADB|REDIS|MONGO|MONGODB|AMQP|RABBIT|RABBITMQ|KAFKA|ELASTIC|ELASTICSEARCH)[A-Z_]*_(URI|URL|HOST)$'
# Only the names finish writes: agent-friendliness-report-20261103T155624Z.md. A
# repo's own -guide.md or -parser.py isn't a past result.
report_glob=':(glob)**/agent-friendliness-report-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z.md'
state_fields='sandbox scored_repo commit base_commit save_dir previous_run owner_pid started settled'

die() { echo "sandbox.sh: $*" >&2; exit 1; }
damaged() {
  die "$*
If this state file is damaged, check no other session is using it, then run preflight. Delete only a leftover_clone folder, named afs-sandbox.* and holding .afs-sandbox. Never delete a path just because the state file records it. Then remove $state_file
If no leftover_clone is listed, remove the state file only and leave any folder alone."
}
hash8() { git hash-object --stdin | cut -c1-8; }
slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9._]+/-/g; s/^-+//; s/-+$//'; }
credentials() { compgen -e | grep -E "$credential_names" | sort || true; }
sandbox_git() { git -C "$sandbox" -c core.hooksPath=/dev/null "$@"; }

scored_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "run this from inside the scored repo"
}

# The same repo gets the same id over HTTPS or SSH, and credentials in the URL
# never reach the id. A repo with no remote falls back to its root commit, and
# its name comes from the common git dir so linked worktrees share an id.
repo_id() {
  local remote url common
  scored_root >/dev/null
  remote=$(git remote | grep -x origin || git remote | head -1 || true)
  if [ -n "$remote" ]; then
    url=$(git remote get-url "$remote" | tr 'A-Z' 'a-z' | sed -E \
      -e 's#^[a-z+]+://##' -e 's#^[^/@]*@##' -e 's#^([^/:]+):[0-9]+/#\1/#' \
      -e 's#^([^/:]+):#\1/#' -e 's#/+$##' -e 's#\.git$##')
    printf '%s-%s' "$(slug "${url##*/}")" "$(printf '%s' "$url" | hash8)"
  else
    common=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
    printf '%s-%s' "$(slug "$(basename "$common")")" \
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

# Reads known key=value lines into variables. Nothing in the file is executed.
read_state() {
  local line field
  for field in $state_fields; do printf -v "$field" '%s' ""; done
  while IFS= read -r line || [ -n "$line" ]; do
    case " $state_fields " in
      *" ${line%%=*} "*) printf -v "${line%%=*}" '%s' "${line#*=}" ;;
    esac
  done < "$1"
}

write_state() {
  local field value
  (
    umask 077
    for field in $state_fields; do
      eval "value=\${$field:-}"
      case "$value" in *"
"*) die "a path holds a line break, which the state file can't record" ;; esac
      printf '%s=%s\n' "$field" "$value"
    done > "$state_file.new"
  )
  mv "$state_file.new" "$state_file"
}

orphans() {
  local dir state known physical
  for dir in "$tmp_root"/afs-sandbox.??????; do
    [ -d "$dir" ] && [ ! -L "$dir" ] && [ -f "$dir/.afs-sandbox" ] || continue
    physical=$(cd "$dir" && pwd -P)
    known=no
    for state in "$base"/.active/*.env; do
      [ -f "$state" ] || continue
      read_state "$state"
      [ "$sandbox" = "$physical/repo" ] && known=yes
    done
    [ "$known" = yes ] || echo "leftover_clone=$dir"
  done
  return 0
}

load_state() {
  state_file="$base/.active/$(repo_id).env"
  [ -f "$state_file" ] || die "no active run for this repo. Run setup from the scored repo."
  read_state "$state_file"
}

# Checks the recorded path has the shape setup creates, setting clone_problem and
# returning 1 if it doesn't. The folder itself is only checked when it exists,
# because finish may run after it was removed.
clone_path_ok() {
  clone_problem=""
  parent=""
  case "$sandbox" in
    /*/repo) ;;
    *) clone_problem="the recorded clone path, '$sandbox', isn't one setup creates."; return 1 ;;
  esac
  case "$sandbox/" in
    */../*|*/./*|*//*) clone_problem="the recorded clone path, '$sandbox', isn't normalised."; return 1 ;;
  esac
  parent=${sandbox%/repo}
  case "${parent##*/}" in
    afs-sandbox.??????) ;;
    *) clone_problem="the recorded clone path, '$sandbox', isn't one setup creates."; return 1 ;;
  esac
  if [ -e "$parent" ]; then
    [ "$(cd "$parent" && pwd -P)" = "$parent" ] || { clone_problem="$parent isn't a real path."; return 1; }
    [ -f "$parent/.afs-sandbox" ] || { clone_problem="$parent has no marker from setup."; return 1; }
  fi
}

check_clone_path() {
  clone_path_ok || damaged "$clone_problem Refusing."
}

guard() {
  load_state
  [ -n "$scored_repo" ] || damaged "the state file has no scored repo."
  case "$commit$base_commit" in *[!0-9a-f]*|"") damaged "the state file has a bad commit." ;; esac
  case "$save_dir/" in
    */../*) damaged "the recorded save folder isn't normalised. Refusing." ;;
    "$base"/*) ;;
    *) damaged "the recorded save folder is outside $base. Refusing." ;;
  esac
  [ "$(scored_root)" = "$scored_repo" ] || die "run this from the scored repo, $scored_repo"
  check_clone_path
  [ "$sandbox" != "$scored_repo" ] || damaged "the clone path is the scored repo. Refusing."
  [ "$(git -C "$sandbox" rev-parse --show-toplevel 2>/dev/null)" = "$sandbox" ] \
    || damaged "$sandbox is not its own git toplevel. Refusing."
  [ -z "$(git -C "$sandbox" remote)" ] || damaged "$sandbox has a remote, so it isn't the throwaway clone. Refusing."
  touch "$state_file"
}

# Checks a report folder chosen by the user, setting report_folder to its absolute
# path, or report_problem and returning 1. It may not exist yet. Anything that
# does exist is resolved, so a symlink can't lead out of the scored repo.
report_folder_ok() {
  local path="$1" root="$2" dir physical resolved
  report_folder=""
  report_problem=""
  case "$path" in
    "") report_problem="no folder given"; return 1 ;;
    *"
"*) report_problem="the path holds a line break"; return 1 ;;
    .) path=$root ;;
    ./*) path=${path#./} ;;
  esac
  case "/$path/" in
    */../*|*/./*) report_problem="the path can't contain . or .. : $path"; return 1 ;;
  esac
  case "$path" in
    /*) report_folder=$path ;;
    *) report_folder="$root/$path" ;;
  esac
  while [ "$report_folder" != "/" ] && [ "${report_folder%/}" != "$report_folder" ]; do
    report_folder=${report_folder%/}
  done
  dir=$report_folder
  while [ ! -e "$dir" ] && [ ! -L "$dir" ]; do dir=$(dirname "$dir"); done
  if [ ! -d "$dir" ]; then
    report_problem="$dir isn't a folder"; return 1
  fi
  physical=$(cd "$dir" && pwd -P)
  resolved="$physical${report_folder#"$dir"}/"
  case "$resolved" in
    "$root"/*) ;;
    *) report_problem="$path is outside the scored repo, $root, or a symlink leads out of it"; return 1 ;;
  esac
  case "${resolved#"$root"}" in
    */.git/*) report_problem="$path is inside a .git folder"; return 1 ;;
  esac
}

# Writes to a temp file first, so a full disk can't leave half a report at the
# target. ln fails if the name exists and doesn't follow a symlink there. The check
# before it is for a directory at the target, which ln would link inside.
publish_report() {
  (
    umask 077
    mkdir -p "$report_folder" || exit 1
    report_tmp=$(mktemp "$report_folder/.agent-friendliness-report.XXXXXX") || exit 1
    trap 'rm -f "$report_tmp"' EXIT
    cat "$save_dir/report.md" > "$report_tmp" || exit 1
    [ ! -e "$target" ] && [ ! -L "$target" ] || exit 1
    ln -n "$report_tmp" "$target" || exit 1
  ) 2>/dev/null
}

need_settled() {
  [ "$settled" = yes ] && return 0
  die "run sandbox settle first. It commits everything in the clone, as install output. If you've edited files, save the edit elsewhere first, then run sandbox restore, sandbox settle, and redo the edit."
}

in_save_dir() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *..*) die "bad relative path: $1" ;;
    *) printf '%s/%s' "$save_dir" "$1" ;;
  esac
}

# Prints the problem and returns 1 if the save folder can't be used. The save
# folder stays outside the scored repo, because the clone's state and patches live
# there, so this runs before anything is created. The one file written to the
# checkout is the report copy from finish --report-to.
save_folder_problem() {
  local root="$1" dir physical probe
  case "$base" in
    /*) ;;
    *) echo "AFS_HOME must be an absolute path: $base"; return 1 ;;
  esac
  case "$base/" in
    */../*|*/./*) echo "AFS_HOME must not contain . or .. : $base"; return 1 ;;
  esac
  dir=$base
  while [ ! -d "$dir" ]; do dir=$(dirname "$dir"); done
  physical=$(cd "$dir" && pwd -P)
  case "$physical${base#"$dir"}/" in
    "$root"/*) echo "$base is inside the scored repo"; return 1 ;;
  esac
  if ! ( umask 077; mkdir -p "$base" ) 2>/dev/null \
    || ! probe=$(mktemp "$base/.probe.XXXXXX" 2>/dev/null); then
    echo "$base can't be written"; return 1
  fi
  rm -f "$probe"
}

cmd_preflight() {
  local blocked=0 root probe url problem file files="" state_summary
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
  if problem=$(save_folder_problem "$root"); then
    echo "save_write=ok ($base)"
  else
    echo "save_write=blocked ($problem)"; blocked=1
  fi
  if ! command -v gh >/dev/null; then echo "gh=not installed"
  elif gh api rate_limit >/dev/null 2>&1; then echo "gh=ok"
  else echo "gh=unavailable (not logged in or no network)"; fi
  for url in "${@:-https://github.com}"; do
    if ! command -v curl >/dev/null; then echo "network=unknown, no curl ($url)"
    elif curl -sS -o /dev/null --max-time 8 -I "$url" 2>/dev/null; then echo "network=ok ($url)"
    else echo "network=blocked ($url)"; fi
  done
  echo "credentials_unset_for_test_runs=$(credentials | paste -sd, -)"
  for file in .aws .kube/config .pgpass .netrc; do
    [ ! -e "$HOME/$file" ] || files="$files${files:+,}~/$file"
  done
  echo "credential_files_tests_can_read=$files"
  state_file="$base/.active/$(repo_id).env"
  if [ -f "$state_file" ]; then
    read_state "$state_file"
    # Only repeat a path this script would act on. A damaged state file could
    # record any folder, and this output guides what gets deleted by hand.
    if clone_path_ok && [ -f "$parent/.afs-sandbox" ]; then
      state_summary="clone=$sandbox"
    else
      state_summary="clone=unverified"
    fi
    state_summary="$state_summary started=$started owner_pid=$owner_pid"
    if [ -n "$(find "$state_file" -mmin -10 2>/dev/null)" ]; then state_summary="$state_summary used_in_last_10_minutes=yes"
    else state_summary="$state_summary used_in_last_10_minutes=no"; fi
    echo "active_run=$state_file $state_summary"
  fi
  orphans
  [ "$blocked" = 0 ] || exit 1
}

cmd_setup() {
  local scope="${1:-}" id root run_dir stamp dir problem
  root=$(scored_root)
  git rev-parse --verify -q HEAD >/dev/null \
    || { echo "This repo has no commits, so there's nothing to score." >&2; exit 3; }
  problem=$(save_folder_problem "$root") || die "can't use the save folder: $problem"
  id=$(repo_id)
  state_file="$base/.active/$id.env"
  [ ! -f "$state_file" ] || die "a run is already active or crashed: $state_file. Run preflight to see it."
  scored_repo=$root
  commit=$(git rev-parse HEAD)
  base_commit=$commit
  settled=no
  owner_pid=$PPID
  started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  run_dir="$base/$id${scope:+--$(slug "$scope")}"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  save_dir="$run_dir/$stamp"
  previous_run=""
  for dir in "$run_dir"/*/; do
    [ ! -f "${dir}complete" ] || previous_run="${dir%/}"
  done
  ( umask 077
    mkdir -p "$base/.active" "$save_dir/seeded" "$save_dir/violations" "$save_dir/context" )

  parent=$(mktemp -d "$tmp_root/afs-sandbox.XXXXXX")
  parent=$(cd "$parent" && pwd -P)
  trap 'rm -rf "$parent"' EXIT
  : > "$parent/.afs-sandbox"
  sandbox="$parent/repo"
  # No --local: that makes a failed hard link fatal when the clone is on another
  # mount. A plain clone of a path still hard links, and copies if it can't.
  git -c core.hooksPath=/dev/null clone --quiet --no-checkout --template= -o origin -- "$root" "$sandbox"
  # A detached HEAD in a linked worktree isn't copied by clone, so fetch it.
  git -C "$sandbox" cat-file -e "$commit^{commit}" 2>/dev/null \
    || sandbox_git fetch --quiet "$root" "$commit"
  git -C "$sandbox" remote remove origin
  sandbox_git checkout --quiet --detach "$commit"
  ( umask 077; snapshot "$root" > "$save_dir/scored-repo-before.txt" )
  write_state
  trap - EXIT
  cmd_paths
  [ ! -f "$root/.gitmodules" ] || echo "warning=submodules are not in the clone"
  ! grep -qs 'filter=lfs' "$root/.gitattributes" || echo "warning=Git LFS files are pointers in the clone"
  [ "$(git rev-parse --is-shallow-repository)" = false ] \
    || echo "warning=shallow clone, so history-based checks are not measured"
  orphans
}

# Looks for docs/ then doc/ at the repo root, or the root of a scoped package.
cmd_find_report_folder() {
  local scope="${1:-}" root start name found=none
  root=$(scored_root)
  start=$root
  if [ -n "$scope" ]; then
    report_folder_ok "$scope" "$root" || die "bad scope: $report_problem"
    start=$report_folder
  fi
  for name in docs doc; do
    [ -d "$start/$name" ] || continue
    if report_folder_ok "$start/$name" "$root"; then
      found=${report_folder#"$root"/}
      break
    fi
    echo "report_folder_skipped=$name ($report_problem)"
  done
  echo "report_folder=$found"
}

cmd_check_report_folder() {
  [ "$#" = 1 ] || die "usage: check-report-folder <folder>"
  report_folder_ok "$1" "$(scored_root)" || die "can't save the report there: $report_problem"
  echo "report_folder=$report_folder"
}

cmd_paths() {
  [ -n "${sandbox:-}" ] || load_state
  echo "sandbox=$sandbox"
  echo "commit=$commit"
  echo "save_dir=$save_dir"
  echo "previous_run=$previous_run"
}

cmd_run() {
  local keep="" status=0 started_at=$SECONDS
  while [ "${1:-}" = "--keep" ]; do
    case "${2:-}" in
      ""|*[!A-Za-z0-9_]*) die "usage: run --keep NAME -- <command>" ;;
    esac
    keep="$keep $2 "
    shift 2
  done
  [ "${1:-}" = "--" ] && shift
  [ "$#" -gt 0 ] || die "usage: run [--keep NAME] -- <command>"
  guard
  [ -z "$keep" ] || echo "kept_credentials=$keep" >&2
  (
    umask "$caller_umask"
    cd "$sandbox" || exit 125
    unset GIT_LFS_SKIP_SMUDGE GIT_OPTIONAL_LOCKS
    for name in $(credentials); do
      case "$keep" in *" $name "*) ;; *) unset "$name" ;; esac
    done
    exec "$@"
  ) || status=$?
  echo "exit=$status elapsed_seconds=$((SECONDS - started_at))" >&2
  return "$status"
}

# Commits what install left behind, inside the clone only, and restores to that
# commit from now on. Without this, a changed lockfile would land in the first
# patch and the first restore would delete it.
cmd_settle() {
  [ "$#" = 0 ] || [ "${1:-}" = "--reinstall" ] || die "usage: settle [--reinstall]"
  guard
  # A second settle would commit any applied patch into every later run.
  if [ "$settled" = yes ] && [ "${1:-}" != "--reinstall" ] && [ -n "$(sandbox_git status --porcelain)" ]; then
    die "already settled, and the clone has changes. Run sandbox restore to drop them. After a genuine second install, use sandbox settle --reinstall."
  fi
  # A committed report lists which seeded bugs survived, so agents in this run
  # shouldn't find it. Git history can still show it, which the prompts cover.
  local reports
  reports=$(sandbox_git ls-files -- "$report_glob")
  if [ -n "$reports" ]; then
    sandbox_git rm --quiet -f -- "$report_glob"
    echo "earlier_reports_removed_from_clone=$(printf '%s\n' "$reports" | wc -l | tr -d ' ')"
  fi
  sandbox_git add -A
  if ! sandbox_git diff --cached --quiet; then
    sandbox_git diff --cached --name-only > "$save_dir/install-changes.txt"
    sandbox_git -c user.name=agent-friendliness-score -c user.email=sandbox@invalid \
      -c commit.gpgsign=false commit --quiet --no-verify -m "Install output, clone only"
    echo "install_changed_tracked_files=$(wc -l < "$save_dir/install-changes.txt" | tr -d ' ') (see install-changes.txt)"
  fi
  base_commit=$(sandbox_git rev-parse HEAD)
  settled=yes
  write_state
  echo "restore_point=$base_commit"
}

cmd_apply() {
  [ "$#" = 1 ] || die "usage: apply <patch>"
  guard
  need_settled
  local patch
  patch=$(in_save_dir "$1")
  [ -f "$patch" ] || die "no such patch: $patch"
  sandbox_git apply --whitespace=nowarn --check "$patch"
  sandbox_git apply --whitespace=nowarn "$patch"
}

cmd_capture() {
  [ "$#" = 1 ] || die "usage: capture <path relative to the save folder>"
  guard
  need_settled
  local patch
  case "$1" in /*) die "capture takes a relative path" ;; esac
  patch=$(in_save_dir "$1")
  ( umask 077
    mkdir -p "$(dirname "$patch")"
    sandbox_git add -A .
    sandbox_git diff --cached -U3 --binary --no-ext-diff --no-textconv --no-color --no-relative \
      --src-prefix=a/ --dst-prefix=b/ > "$patch" )
  [ -s "$patch" ] || { rm -f "$patch"; die "the clone has no changes to capture"; }
  # The changes are still applied, so test that the patch reverses cleanly.
  sandbox_git apply --whitespace=nowarn --check -R "$patch" \
    || die "the saved patch doesn't match the clone's changes. The clone is unchanged: $patch"
  cmd_restore
}

cmd_restore() {
  guard
  sandbox_git reset --quiet --hard HEAD
  sandbox_git clean -ffdq
  # Something in the run moved HEAD, for example a test that made a commit.
  [ "$(sandbox_git rev-parse HEAD)" = "$base_commit" ] \
    || sandbox_git checkout --quiet --force --detach "$base_commit"
  [ -z "$(sandbox_git status --porcelain)" ] \
    || die "the clone isn't clean after restoring: $(sandbox_git status --porcelain | head -5)"
}

cmd_finish() {
  local complete=no status=0 report_to="" have_report_to=no target
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --complete) complete=yes; shift ;;
      --report-to)
        [ "$#" -ge 2 ] || die "usage: finish [--complete [--report-to <folder>]]"
        report_to=$2; have_report_to=yes; shift 2 ;;
      *) die "usage: finish [--complete [--report-to <folder>]]" ;;
    esac
  done
  load_state
  check_clone_path
  if [ "$complete" = yes ]; then
    [ -f "$save_dir/report.md" ] && [ -f "$save_dir/result.json" ] \
      || die "save report.md and result.json in $save_dir before finishing with --complete"
  fi
  # Refuse a bad report folder now, while the run can still be fixed.
  if [ "$have_report_to" = yes ]; then
    [ "$complete" = yes ] || die "--report-to needs --complete, because it copies the finished report"
    [ "$(scored_root)" = "$scored_repo" ] || die "run this from the scored repo, $scored_repo"
    report_folder_ok "$report_to" "$scored_repo" || die "can't save the report there: $report_problem"
  fi
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
  # This comes after the comparison above, so the copy doesn't count as a change.
  # It's checked again because the run may have changed the folder.
  if [ "$have_report_to" = yes ]; then
    target="$report_folder/agent-friendliness-report-$(basename "$save_dir").md"
    if report_folder_ok "$report_to" "$scored_repo" && publish_report; then
      echo "report_copy=$target"
      echo "report_copy_note=untracked, and not staged or committed"
    else
      echo "report_copy=FAILED: couldn't write $target ${report_problem:+($report_problem) }. The report is still at $save_dir/report.md. Read the scored_repo line above too, because this exit code hides a change to the scored repo." >&2
      status=5
    fi
  fi
  exit "$status"
}

command="${1:-}"
[ "$#" = 0 ] || shift
case "$command" in
  preflight|setup|paths|run|settle|apply|capture|restore|finish) "cmd_$command" ${1+"$@"} ;;
  find-report-folder) cmd_find_report_folder ${1+"$@"} ;;
  check-report-folder) cmd_check_report_folder ${1+"$@"} ;;
  *) die "usage: sandbox.sh preflight|setup [scope]|paths|run [--keep NAME] -- <command>|settle [--reinstall]|apply <patch>|capture <path>|restore|find-report-folder [scope]|check-report-folder <folder>|finish [--complete [--report-to <folder>]]" ;;
esac
