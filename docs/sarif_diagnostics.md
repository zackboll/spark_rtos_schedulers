# Native GNATprove SARIF diagnostic audit

This document inventories the unchanged native GNATprove SARIF from the first
successful hosted upload. It explains the evidence; it does not filter results,
add or remove suppressions, dismiss GitHub alerts, or create an expected-warning
allowlist.

## Evidence identity and counting method

- Repository: `zackboll/spark_rtos_schedulers`
- Hosted workflow run: [`35042916820`](https://github.com/zackboll/spark_rtos_schedulers/actions/runs/35042916820), attempt 1
- Commit: `e1cac6a9e596eaf44a469fceb7d481e97911da75`
- Hosted conclusion: successful (proof gate, SARIF processing, evidence upload,
  and dependent build)
- GNATprove: `FSF 16.1.0` (native SARIF driver name `GNATProve`, organization
  `AdaCore`)
- Native report: SARIF 2.1.0, `gnatprove.sarif`, SHA-256
  `49be6e9cc154e1b9c83a687d2bc1965ed72090adbda7153d1ef3e3d59bac8662`
- Text report: `gnatprove.out`, generated with `--mode=all -U --level=2
  --timeout=0 --steps=10000000 --checks-as-errors=on`; its summary is
  1,190/1,190 checks discharged, zero justified and zero unproved.

The inventory iterates every object in `runs[].results` and groups on literal
`ruleId`, `kind`, `level`, and exact message text. It does **not** count rule
descriptors or console lines. The native file has 1,417 records: 1,194
`kind=pass`/`level=none` and 223 `kind=open`/`level=warning`. Of all records,
1,224 point into this repository and 193 point to the installed runtime source.
There are 117 distinct rule/kind/level/message signatures and 1,108 distinct
physical source locations across pass and non-pass records.

`gnatprove-upload.sarif` was used only to verify source mapping. It retains all
1,417 results and changes uniquely matched scheduler basenames to `src/...`;
the native file above remains the authoritative unchanged evidence.

The 1,190 proof-summary checks and 1,417 SARIF result records are different
populations. SARIF includes successful checks, flow results, informational
records, and warnings. Neither number is the number of currently open GitHub
alerts. Repeated records can arise at many uses of one modeled dependency and
are not necessarily independent assumptions or verification conditions.

## Non-pass inventory for this baseline

All rows below are observations for commit `e1cac6a…`, run `35042916820`, not
permanent acceptance thresholds.

| Rule/message family | Native kind/level | Baseline records | Representative location | Meaning and project implication | Disposition / unresolved question | Supporting source |
|---|---|---:|---|---|---|---|
| `error`: `function Is_Valid is assumed to return True` | `open` / `warning` | 193 (179 at line 36; 14 at line 60) | `a-nbnbin.ads:36:32`, `a-nbnbin.ads:60:17` | GNATprove relies on the intrinsic validity predicate of the standard arbitrary-precision integer implementation. Here this supports `Valid_Big_Integer` and `Big_Natural`; it is a library/runtime trust boundary, not an error-level result despite the generic rule ID. | **Proof-model/external dependency.** Retain and expose. The available evidence does not establish why GNATprove emits one record at each propagated use rather than coalescing them; do not read 193 as 193 independent unproved VCs. | Installed GNAT 16.1.0 `a-nbnbin.ads`, lines 26–36 and 58–62; SPARK UG, “Big Numbers Library” and “Writing Contracts on Imported Subprograms”. |
| `operator-reassociation`: `possible reassociation due to missing parentheses [operator-reassociation]` | `open` / `warning` | 11 | `rtos-indexed_scheduler.ads:849:19`; `.adb:522:15` | Parenthesization can affect intermediate overflow for bounded integer arithmetic. The sites are `Natural`-derived `Ready_Count_Type`/`Global_Occurrence_Count` additions: the eight-priority sum and state-count `+ 1` expressions. Separate overflow/range VCs passed, but the warning identifies expression grouping that is less explicit to analysis and readers. | **Source-quality/analysis-precision warning.** Later cleanup may parenthesize the intended grouping, after reviewing each expression; no source change in this audit. | Baseline declarations at `.ads:39`, `.ads:142-146`, `.ads:848-850`; SPARK UG, “Overflow Modes” and warning guidance. |
| `contracts-recursive`: `function contract might not be available on recursive calls [contracts-recursive]` | `open` / `warning` | 4 | `rtos-indexed_scheduler.ads:121:13`, `:339:13`, `:354:13`, `:372:13` | Calls inside recursive `Ready_Prefix`, `Follow`, `Length_Prefix`, and `Occurrence_Prefix` cannot necessarily use the function contract in the same way as ordinary calls. This says proof information may be unavailable; it does not say the contract was assumed true without proof. | **Analysis-precision limitation.** Review explicit recursion lemmas/contracts if future proofs need the unavailable facts. | SPARK UG, “Expression Functions” and “Subprogram Termination”. |
| `contracts-recursive`: `implicit function contract might not be available on recursive calls [contracts-recursive]` | `open` / `warning` | 2 | `rtos-pointer_scheduler.ads:332:13`, `:364:13` | The implicit expression-function contracts for recursive `List_Length` and `Occurrences` may be unavailable on recursive calls. Both are Ghost structural list models. | **Analysis-precision limitation.** Retain; consider explicit contracts only if later proof work requires them. | Baseline source at `.ads:329-369`; SPARK UG, “Expression Functions”. |
| `numeric-variant`: `expression function body of subprograms with a numeric variant might not be available on recursive calls [numeric-variant]` | `open` / `warning` | 5 | `rtos-indexed_scheduler.ads:121:13`, `:339:13`, `:354:13`, `:372:13`, `:437:13` | Numeric variants prove decreasing recursion/termination, but GNATprove may not make an expression body available recursively. This is unavailable prover information, not an assumed functional fact. `Path_Avoids` is the fifth bounded-fuel Ghost function. | **Analysis-precision limitation.** Review only if it blocks later model proofs. | SPARK UG, “Subprogram Termination”; baseline `Subprogram_Variant` declarations. |
| `array-initialization`: `initialization of an array in FOR loop is handled imprecisely [array-initialization]` | `open` / `warning` | 1 | `rtos-pointer_scheduler.adb:77:10` | A loop fills the Ghost `Ready_Occurrence_Map` result from `Ready_Occurrences`; GNATprove warns that flow initialization tracking for that loop is imprecise. It is not a statement that an element is actually uninitialized. | **Analysis-precision limitation.** Keep visible; revisit loop shape only if a real initialization proof is obscured. | Baseline `Copy_Ready_Occurrences` body, lines 71–83; SPARK UG warning guidance. |
| `INEFFECTIVE`: `initialization of "Result" has no effect` | `open` / `warning` | 3 | `rtos-pointer_scheduler.adb:6:7`, `:17:7`, `:208:7` | Whole-array initial values are overwritten by loops in Ghost model helpers (`Ready_Lengths`, `Occurrences_By_Priority`, and `Contents`). | **Source-quality warning.** Candidate cleanup after this audit, with proof revalidation. | Baseline bodies at the listed locations. |
| `INEFFECTIVE`: `"Node" is set by "Append_Ready_Tail" but not used after the call` | `open` / `warning` | 3 | `rtos-pointer_scheduler.adb:383:42`, `:415:42`, `:530:42` | Ownership-transfer calls null the local access value; callers do not subsequently read it. | **Source-quality warning.** Potential API/call-site cleanup, but ownership semantics require care. | Baseline `Make_Ready`, `Yield`, and `Schedule` call sites. |
| `INEFFECTIVE`: `"Node" is set by "Release_Node" but not used after the call` | `open` / `warning` | 1 | `rtos-pointer_scheduler.adb:470:34` | The release operation transfers ownership and updates the local, which is then dead. | **Source-quality warning.** Same deferred ownership-aware cleanup. | Baseline `Select_Next` call site. |

The non-pass family counts sum to 223: 193 + 11 + 6 + 5 + 1 + 7.
For additional context, native SARIF also uses literal rule ID `error` for four
`kind=pass`, `level=none` loop-unrolling information records. This confirms why
classification must use message, kind, and level rather than rule ID alone.

## `Is_Valid` boundary and actual project use

The referenced declaration is specifically
`Ada.Numerics.Big_Numbers.Big_Integers.Is_Valid (Arg : Big_Integer)`, declared
with `Convention => Intrinsic` and `Global => null` in the exact GNAT 16.1.0
runtime source installed at:

```text
/home/zboll/.alire/libexec/spark/lib/gcc/x86_64-pc-linux-gnu/16.1.0/
  adainclude/a-nbnbin.ads
```

`Valid_Big_Integer` has dynamic predicate `Is_Valid`, and `Big_Natural` tests
`Is_Valid` before applying its nonnegative predicate. GNATprove documents that
intrinsic subprograms are handled specially and that bodies outside the
analysis boundary are consumed through their modeled interface. The native
message states the operative fact directly: for this intrinsic library
validity function, GNATprove assumes a true result. It does **not** establish a
general policy for arbitrary user-defined functions named `Is_Valid`.

The pointer scheduler imports this package and declares list lengths,
occurrence counts, arrays of those values, and arithmetic over them as
`Big_Natural`. The recursive model functions (`List_Length`, `Occurrences`) and
the copy/aggregate helpers are marked `Ghost`; their values also appear in
preconditions, postconditions, invariants, lemmas, and `pragma Assert` proof
expressions. These values support specification and verification and do not
form ordinary scheduler state. Whether Ghost computations and their associated
assertions execute depends on the applicable assertion policies and build
configuration; contracts and assertions have their own applicable assertion
policies. When enabled, these computations can perform big-integer calculations
at runtime; when disabled, the corresponding Ghost code is omitted. Ghost
classification is therefore not, by itself, evidence that generated code
contains no Ghost computations, and this audit has not established which
computations are present in every build profile. The mathematical-model and
library trust-boundary discussion remains valid; it is not evidence of ordinary
runtime big-integer scheduler state.

The current proof establishes the reported scheduler checks under GNATprove's
model, including this library boundary and all other modeled assumptions. It
does not independently verify the runtime implementation of arbitrary-
precision integers, prove that every possible concrete `Big_Integer` value is
valid, or turn a conditional proof into unconditional end-to-end runtime
correctness. “All checks passed” is not, by itself, a reason to disregard the
warning.

## Suppression and publication semantics

Exactly 23 native records contain the exact SARIF member
`"suppressions":[{"kind":"external"}]`: all 11 reassociation, all 6
recursive-contract, all 5 numeric-variant, and the one array-initialization
record. The seven `INEFFECTIVE` and 193 `Is_Valid` records contain no
`suppressions` member. The inventory preserves this distinction exactly.

SARIF `kind=external` identifies a suppression supplied outside the result's
analysis rule; because these entries contain no status or justification, this
audit does not invent one. In particular, it does not imply that the project
author added `pragma Warnings`, `Annotate`, `Assume`, or `Suppress`. Native tool
metadata, user-authored proof suppressions/justifications, and GitHub's alert
dismissal state are separate data. No alert was dismissed and no record, kind,
level, message, or suppression was rewritten to make a dashboard cleaner.

## References

- [SPARK User's Guide — SPARK Libraries / Big Numbers Library](https://docs.adacore.com/spark2014-docs/html/ug/en/source/spark_libraries.html#big-numbers-library)
- [SPARK User's Guide — How to Write Subprogram Contracts](https://docs.adacore.com/spark2014-docs/html/ug/en/source/how_to_write_subprogram_contracts.html)
- [SPARK User's Guide — How to Investigate Unproved Checks](https://docs.adacore.com/spark2014-docs/html/ug/en/source/how_to_investigate_unproved_checks.html)
- [SPARK User's Guide — Suppressing and managing assumptions](https://docs.adacore.com/spark2014-docs/html/ug/en/source/how_to_use_gnatprove_in_a_team.html)
- [SPARK User's Guide — Ghost Code](https://docs.adacore.com/spark2014-docs/html/ug/en/source/specification_features.html#ghost-code)
- [SPARK User's Guide — Pragma Assertion_Policy](https://docs.adacore.com/spark2014-docs/html/ug/en/source/assertion_pragmas.html#pragma-assertion-policy)
- [SARIF 2.1.0 `suppression` object](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)

A successful proof remains conditional on the modeled environment. This audit
does not broaden the pointer scheduler's documented Gold scope or the indexed
scheduler's existing proof-status claims.