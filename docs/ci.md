# Continuous verification

The [`SPARK Verification`](../.github/workflows/spark.yml) workflow runs for
every push, every pull request, and manual `workflow_dispatch` requests. CI
begins after GitHub receives a push; this is not a local pre-push hook.

The `SPARK / GNATprove` job resolves the pinned toolchain, tests the report
gate, verifies GNATprove's native `--checks-as-errors=on` behavior in an
isolated temporary project, and then performs complete flow analysis and proof.
Its strict gate requires a successful GNATprove process, a fresh parseable
report, both scheduler units analyzed completely, at least one check, and zero
unproved, justified, or analysis-error results. The generated Alire
configuration unit may remain outside SPARK; neither scheduler is skipped.
GNATprove's native SARIF is collected and validated separately; its publication
does not replace the native process status or strict text-report gate.

Only after proof succeeds does `Ada / Build` run `alr -n build`. Future test or
release jobs should depend on `spark_proof`, or on `build` when they also need
the built library.

## Viewing results

Navigate to **Repository → Actions → SPARK Verification → run**. The run page
shows the proof and dependent build jobs and is also attached as a commit or PR
check. The README badge reports this overall workflow status. The proof job's
GitHub summary reports the checked-out commit, event and ref, tool versions,
actual counts, completeness, proof result, SARIF availability/publication
status, category/method breakdowns, and the original summary table. Step logs
retain failure diagnostics.

The proof step writes provisional artifact data but does not publish it as a
GitHub step summary. After the SARIF upload attempt, a finalizer records its
actual outcome in `summary.json`, regenerates `summary.md`, and a single later
step publishes that authoritative Markdown. Proof and publication outcomes are
separate: a successful proof does not hide a failed upload, and a successful
upload does not turn a failed or missing proof into a pass. For local use,
`spark_report.py run --publish-summary` retains explicit immediate publication.

Native GNATprove findings are uploaded under the stable `spark-gnatprove`
category. After a real remote run, navigate to **Repository → Security → Code
scanning** to inspect source-linked findings. The upload waits for GitHub to
process the report, so rejection fails the workflow as a publication problem,
not as a failed mathematical proof. GitHub supports `upload-sarif` for
`pull_request` runs from forks using the event's built-in token handling; proof
and downloadable evidence still run without secrets. This workflow does not
use `pull_request_target`, a personal token, or CodeQL analysis.

The `spark-proof-…` artifact is retained for 30 days and contains the complete
`gnatprove.log`, fresh `gnatprove.out`, `versions.txt` (including Alire's
dependency solution and toolchain selection), `summary.md`, and `summary.json`,
to the extent those files could be generated before a failure. When available,
it also contains raw native `gnatprove.sarif` and the path-normalized
`gnatprove-upload.sarif` sent to GitHub. The normalized copy changes only
uniquely matched repository source basenames to `src/...`; external runtime
locations remain unchanged. A setup failure is reported as “proof not
completed,” never as zero failures, and missing or invalid SARIF is not
reported as zero findings.

To reproduce the proof command from the repository root:

```sh
alr -n exec -- gnatprove \
  -P spark_rtos_schedulers.gpr \
  -U \
  --mode=all \
  --level=2 \
  --timeout=0 \
  --steps=10000000 \
  --checks-as-errors=on \
  --report=all \
  --output=brief \
  --output-header
```

Command-line `--mode=all` overrides the project's `--mode=prove` switch so CI
runs both flow analysis and proof. The explicit finite step budget avoids
machine-speed-dependent prover cutoffs; the proof job retains a 45-minute
overall timeout. The workflow badge reports the latest
applicable push status on `main`; it does not establish completeness of the
formal requirements. Formal-requirement status remains documented separately
in [`proof_strategy.md`](proof_strategy.md).

An empty code-scanning alert list is not a Gold certificate and does not by
itself establish complete formal verification. Actions summaries provide proof
and completeness counts; code scanning provides source-linked native GNATprove
diagnostics; retained run artifacts provide raw evidence for local inspection.
The baseline native-diagnostic audit is recorded in
[`sarif_diagnostics.md`](sarif_diagnostics.md).

Making the `SPARK / GNATprove` check mandatory before merging requires a
separate GitHub ruleset or branch-protection configuration. This repository
workflow does not alter protection or access settings.