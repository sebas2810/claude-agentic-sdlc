#!/usr/bin/env bash
#
# Both-directions test: a running script must survive being replaced by the very
# apply it is executing.
#
# The defect (observed 2026-08-13): sync-sdlc.sh syncs itself, and used `cp`,
# which rewrites the destination IN PLACE on the same inode. bash reads a script
# lazily by byte offset, so when the file grew 6041 -> 7666 bytes mid-apply, the
# interpreter's next read resumed at a stale offset in different content.
# Everything after that point — the .sdlc-version write and the completion
# message — never executed, exit status looked clean, and the version pin
# silently kept its old value.
#
# This test reproduces the mechanism directly rather than asserting on
# sync-sdlc.sh's internals: a script that grows itself mid-run, once with `cp`
# and once with `mv`.
set -uo pipefail

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# A much larger replacement, so byte offsets shift substantially.
{
  echo '#!/usr/bin/env bash'
  for i in $(seq 1 400); do echo "# filler line $i to shift every byte offset after this point"; done
  echo 'echo REPLACEMENT'
} > "$T/replacement.sh"

# $1 = install method ("cp" or "mv"); writes a victim script that replaces
# itself using that method, then must still print DONE from a later line.
make_victim() {
  cat > "$T/victim.sh" <<EOF
#!/usr/bin/env bash
echo START
if [ "\$1" = "mv" ]; then
  cp -p "$T/replacement.sh" "$T/victim.sh.tmp" && mv -f "$T/victim.sh.tmp" "$T/victim.sh"
else
  cp -p "$T/replacement.sh" "$T/victim.sh"
fi
echo MIDDLE
echo DONE
EOF
  chmod +x "$T/victim.sh"
}

run_victim() { # $1 = method
  make_victim
  bash "$T/victim.sh" "$1" 2>/dev/null
}

echo "── the fix: mv (atomic rename) keeps the running process on its inode ──"
out_mv="$(run_victim mv)"
if printf '%s' "$out_mv" | grep -q DONE; then
  ok "the script completes after replacing itself with mv"
else
  bad "mv path did not reach the end — got: $(printf '%s' "$out_mv" | tr '\n' ' ')"
fi

echo "── anti-tautology: the old cp path must actually break ──"
out_cp="$(run_victim cp)"
if printf '%s' "$out_cp" | grep -q DONE; then
  bad "cp path also completed — this platform does not reproduce the defect, so the mv result proves nothing here"
else
  ok "cp path is truncated mid-run, exactly as observed in the incident"
fi

echo "── the real script uses the safe form ──"
SYNC="$(cd "$(dirname "$0")/.." && pwd)/sync-sdlc.sh"
if [ -f "$SYNC" ]; then
  if grep -qE '^\s*cp -p "\$TMPDIR/canonical/\$f" "\$ROOT/\$f"' "$SYNC"; then
    bad "sync-sdlc.sh still installs with a direct in-place cp"
  else
    ok "sync-sdlc.sh no longer installs with a direct in-place cp"
  fi
  if grep -q 'mv -f' "$SYNC"; then
    ok "sync-sdlc.sh installs via an atomic rename"
  else
    bad "sync-sdlc.sh has no atomic rename"
  fi
else
  bad "could not locate sync-sdlc.sh at $SYNC"
fi

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $((fails > 0))
