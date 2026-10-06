#!/usr/bin/env bash
# This repo is public. Block anything that would publish a secret or identify the
# owner's employer, orgs or accounts.
#
# Generic rules live in this file. Private words (employer, org names, real org IDs)
# live in .git/info/sensitive-patterns, one per line. Git never commits files inside
# .git/, so the private list can't leak.
#
# Usage:
#   scan-sensitive.sh --staged          added lines and files in the index (pre-commit)
#   scan-sensitive.sh --message FILE    a commit message (commit-msg)
#   scan-sensitive.sh --push FROM TO    commits FROM..TO, or all of TO if FROM is empty (pre-push)
#   scan-sensitive.sh --all             every tracked file (manual audit)
set -uo pipefail

git_dir=$(git rev-parse --git-dir)
private_file="$git_dir/info/sensitive-patterns"

# Extended regexes, matched case-insensitively.
generic=(
  'sk-ant-[a-z0-9_-]{8,}'
  'sessionkey[^a-z0-9]{0,4}[:=]'
  'bearer +[a-z0-9._~+/-]{20,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'gh[pousr]_[a-z0-9]{30,}'
  '/Users/[a-z0-9._-]+/'
  '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
  '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
)
# A match is fine if the matched text contains one of these.
allow='00000000-0000-|@example\.(com|org)|noreply@anthropic\.com|@users\.noreply\.github\.com|/Users/you/'

# Files that should never be published, even if someone force-adds them.
blocked_files='\.(jsonl|har|sqlite|sqlite-wal|sqlite-shm|cookies|env)$|(^|/)\.env|(^|/)(\.superpowers|\.playwright-mcp)/'
# Images, video and PDFs can't be scanned; they need a human look first.
media_files='\.(png|jpe?g|gif|heic|webp|mov|mp4|pdf)$'

found=0
complain() { found=1; printf '  %s\n' "$*" >&2; }

private_patterns() {
  [ -f "$private_file" ] || return 0
  grep -v '^[[:space:]]*#' "$private_file" | sed '/^[[:space:]]*$/d'
}

# stdin: lines of "where<TAB>text". Reports every rule hit. Callers feed it with
# < <(...) rather than a pipe, so "found" is set in this shell, not a subshell.
check_lines() {
  local lines re hits pats
  lines=$(cat)
  [ -n "$lines" ] || return 0
  for re in "${generic[@]}"; do
    hits=$(printf '%s\n' "$lines" | grep -Ei -e "$re" | while IFS=$'\t' read -r where text; do
      printf '%s\n' "$text" | grep -Eio -e "$re" | grep -Eiv -e "$allow" | sed "s|^|$where: |"
    done)
    [ -n "$hits" ] && while IFS= read -r h; do complain "$h"; done <<< "$hits"
  done
  pats=$(private_patterns)
  if [ -n "$pats" ]; then
    hits=$(printf '%s\n' "$lines" | grep -Fi -f <(printf '%s\n' "$pats") | cut -f1)
    [ -n "$hits" ] && while IFS= read -r h; do complain "$h: matches a private word (see .git/info/sensitive-patterns)"; done <<< "$hits"
  fi
}

# stdin: unified diff with -U0. stdout: "path:line<TAB>added text".
added_lines() {
  awk '
    /^\+\+\+ / { path = substr($0, 7); next }
    /^@@ / { split($3, a, ","); line = substr(a[1], 2) + 0; next }
    /^\+/ { printf "%s:%d\t%s\n", path, line, substr($0, 2); line++ }
  '
}

check_paths() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf '%s\n' "$p" | grep -Eqi -e "$blocked_files" && complain "$p: this kind of file is never published"
    if printf '%s\n' "$p" | grep -Eqi -e "$media_files" && [ "${CLAUDEDOCK_ALLOW_MEDIA:-}" != 1 ]; then
      complain "$p: images/PDFs can't be scanned. Check it shows no names, emails or real usage, then commit with CLAUDEDOCK_ALLOW_MEDIA=1"
    fi
    [ -n "$(private_patterns)" ] && printf '%s\n' "$p" | grep -Fqi -f <(private_patterns) && complain "$p: file name matches a private word"
  done
}

run_gitleaks() {
  command -v gitleaks >/dev/null || return 0
  gitleaks git --no-banner --redact --log-level=warn "$@" . >&2 || found=1
}

case "${1:-}" in
  --staged)
    check_paths < <(git diff --cached --name-only --diff-filter=ACMR)
    check_lines < <(git diff --cached -U0 --no-color --diff-filter=ACMR | added_lines)
    run_gitleaks --pre-commit --staged
    ;;
  --message)
    check_lines < <(awk '!/^#/ { printf "commit message:%d\t%s\n", NR, $0 }' "$2")
    ;;
  --push)
    from=${2:-}; to=$3
    if [ -n "$from" ]; then base=$from; spec="$from..$to"; else base=$(git hash-object -t tree /dev/null); spec=$to; fi
    check_paths < <(git diff --name-only --diff-filter=ACMR "$base" "$to")
    check_lines < <(git diff -U0 --no-color --diff-filter=ACMR "$base" "$to" | added_lines)
    check_lines < <(for sha in $(git rev-list "$spec"); do
      git log -1 --format=%B "$sha" | awk -v s="${sha:0:8}" '{ printf "message %s:%d\t%s\n", s, NR, $0 }'
      git log -1 --format="commit ${sha:0:8}%x09author %ae committer %ce" "$sha"
    done)
    run_gitleaks --log-opts="$spec"
    ;;
  --all)
    check_paths < <(git ls-files)
    check_lines < <(git ls-files -z | xargs -0 grep -nI '' 2>/dev/null | sed -E 's/^([^:]+:[0-9]+):/\1\t/')
    ;;
  *)
    echo "usage: $0 --staged | --message FILE | --push FROM TO | --all" >&2; exit 2 ;;
esac

if [ ! -f "$private_file" ]; then
  echo "note: no private word list at $private_file, so only the generic checks ran." >&2
fi
if [ "$found" -ne 0 ]; then
  echo "Blocked: this would publish something sensitive (details above). This repo is public." >&2
  exit 1
fi
exit 0
