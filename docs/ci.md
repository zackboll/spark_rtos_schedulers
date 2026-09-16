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

Only after proof succeeds does `Ada / Build` run `alr -n build`. Future test or
release jobs should depend on `spark_proof`, or on `build` when they also need
the built library.

## Viewing results

Navigate to **Repository → Actions → SPARK Verification → run**. The run page
shows the proof and dependent build jobs and is also attached as a commit or PR
check. The proof job's GitHub summary reports the checked-out commit, event and
ref, tool versions, actual counts, completeness, category/method breakdowns,
and the original summary table. Step logs retain failure diagnostics.

The `spark-proof-…` artifact is retained for 30 days and contains the complete
`gnatprove.log`, fresh `gnatprove.out`, `versions.txt` (including Alire's
dependency solution and toolchain selection), `summary.md`, and
`summary.json`, to the extent those files could be generated before a failure.
A setup failure is reported as “proof not completed,” never as zero failures.

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

Making the `SPARK / GNATprove` check mandatory before merging requires a
separate GitHub ruleset or branch-protection configuration. This repository
workflow does not alter protection or access settings.