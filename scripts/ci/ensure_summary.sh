#!/usr/bin/env bash
set -euo pipefail

artifact_dir=${1:-artifacts/spark}
mkdir -p "$artifact_dir"
if [[ ! -f "$artifact_dir/summary.md" ]]; then
  cat >"$artifact_dir/summary.md" <<EOF
# SPARK Verification

**Result: FAIL — proof not completed**

- Repository: \`${GITHUB_REPOSITORY:-unavailable}\`
- Commit: \`${GITHUB_SHA:-unavailable}\`
- Event/ref: \`${GITHUB_EVENT_NAME:-unavailable}\` / \`${GITHUB_REF:-unavailable}\`
- Analysis: \`--mode=all\`, proof level \`2\`
- GNATprove exit status: \`unavailable\`

The proof command did not produce a summary, usually because checkout, toolchain setup, dependency resolution, or a reporting test failed. Missing analysis is not treated as zero failures.
EOF
fi