#!/usr/bin/env bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/negative.gpr" <<'EOF'
project Negative is
   for Source_Dirs use (".");
   for Object_Dir use "obj";
end Negative;
EOF
cat >"$tmp/negative.adb" <<'EOF'
procedure Negative with SPARK_Mode is
begin
   pragma Assert (False); -- Intentionally unprovable CI behavior test.
end Negative;
EOF

set +e
alr -n exec -- gnatprove -P "$tmp/negative.gpr" -u negative.adb \
  --mode=prove --level=0 --checks-as-errors=on --report=all \
  --output=brief --output-header >"$tmp/gnatprove.log" 2>&1
status=$?
set -e
if [[ $status -eq 0 ]]; then
  cat "$tmp/gnatprove.log"
  echo "expected --checks-as-errors=on to reject the unproved assertion" >&2
  exit 1
fi
grep -Eq 'unproved|medium: assertion might fail|high: assertion might fail' "$tmp/gnatprove.log"
echo "native checks-as-errors negative test passed (exit status $status)"