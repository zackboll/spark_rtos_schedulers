# SPARK RTOS Schedulers

[![SPARK Verification](https://github.com/zackboll/spark_rtos_schedulers/actions/workflows/spark.yml/badge.svg?branch=main&event=push)](https://github.com/zackboll/spark_rtos_schedulers/actions/workflows/spark.yml)

This native GitHub Actions badge displays the latest applicable push-workflow
status on `main`. It is workflow status, not evidence that every intended
scheduler requirement has been formalized.

Educational SPARK models of a single-CPU fixed-priority preemptive
scheduler. This is a formal-verification experiment, **not** a
production RTOS: there is no context switch, interrupt handling, SMP,
mutex, or wait-queue implementation.

## Why two schedulers?

The same logical scheduler is being built twice:

1. `RTOS.Pointer_Scheduler` — per-priority singly linked ready lists
   using Ada access types and SPARK ownership/borrowing.
2. `RTOS.Indexed_Scheduler` — the same linked-queue behavior with
   bounded `Task_Id` links instead of pointers, with O(1)
   enqueue, dequeue, and same-priority yield.

The question under investigation is architectural: SPARK's ownership
model allows only one mutable access path to a heap list. A
conventional `Head` plus persistent `Tail` pointer into the same list
is therefore not a legal SPARK design. The pointer model accepts O(N)
tail insertion via a temporary borrower. The indexed model keeps `Head`
and `Tail` because the links are IDs, not writable aliases.

## Current status

The pointer scheduler implements the real behavioral transitions on
the proved list model and reaches the project's SPARK Gold integrity
target for REQ-SCHED-001 through REQ-SCHED-008. Queue nodes represent
READY membership only. Persistent pointer roots remain `Free_Head` and
`Heads (Priority)`. The running task occupies `Current` with scalar
state `Running` and owns no ready node.

- `Initialize` allocates the 16-node pool once and establishes
  `Scheduler_Valid`.
- `Make_Ready` acquires a free node and appends at the ready tail of
  the task's configured priority.
- `Block` blocks the currently running task; it does not remove an
  arbitrary ready node.
- `Select_Next` scans the eight priorities high-to-low, consumes the
  highest nonempty ready head, and returns that node to the free list.
- `Yield` requeues Current at the tail of its own priority, then
  dispatches with `Select_Next`.
- `Schedule` dispatches when idle and preempts only for a strictly
  higher ready priority. Equal-priority tasks rotate only through Yield.

Priority lookup is O(P) with P=8 fixed. Tail insertion remains O(N).
There is no allocation after `Initialize`.

The indexed scheduler is no longer a skeleton. `Task_Id` values are the
linked queue nodes. `Heads(P)`, `Tails(P)`, and `Next(Id)` store
`Optional_Task_Id`. Persistent Head and Tail are legal because they are
identifiers, not writable SPARK access aliases. There is no heap
allocation and no access type in the indexed implementation.

- `Initialize` clears all links, states, and counts.
- `Make_Ready` marks a Dormant or Blocked task Ready and O(1) appends
  it at its configured-priority tail.
- `Block` marks the currently running task Blocked and clears Current;
  ready links are unchanged.
- `Select_Next` scans at most the eight `Nonempty` flags, O(1)
  dequeues the highest nonempty head, and sets that task Running.
- `Yield` requeues Current at its priority tail in O(1), then
  dispatches with `Select_Next`.
- `Schedule` dispatches when idle and preempts only for a strictly
  higher ready priority. Equal-priority tasks do not preempt; they
  rotate only through Yield.

Indexed complexity, with `Priority_Count` statically equal to 8:

- enqueue                    O(1)
- dequeue                    O(1)
- yield queue mutation       O(1)
- preemption queue mutation  O(1)
- priority selection         at most 8 `Nonempty` checks

Selection is therefore constant with respect to task count. The package
does not implement or claim a ready-priority bitmap or a CLZ/bit-scan
selector.

`Indexed_Scheduler_Valid` is a proved local behavioral/structural
layer, not indexed Gold reachability. It currently composes:

- `Scalar_Scheduler_Valid` — at most one Running task, identified by Current
- `Queue_Structure_Valid` — Head/Tail empty equivalence, Nonempty flags, tail terminator
- `Endpoint_Ready_Valid` — existing Head/Tail IDs are Ready at priority P
- `Nonready_Unlinked` — non-Ready tasks have no outgoing Next
- `Next_Edges_Valid` — every non-null Next target is Ready at the source's priority
- `Heads_Unreferenced` — no Next edge points to a current Head
- `Next_Injective` — unique non-null immediate predecessors
- `Ready_Count_State_Valid` — `Ready_Count` equals the number of tasks whose scalar state is Ready

`Ready_Count_State_Valid` is scalar accounting. It does **not** prove
that `Ready_Count` equals the total length of all Head/Next chains.
`Next_Injective` proves unique immediate predecessors; it does **not**
by itself prove global acyclicity, global membership uniqueness, or
reachability from a Head. Complete Head-chain reachability remains the
next indexed Gold layer.

Pointer `Scheduler_Valid` composes four proved predicates:

- `Representation_Valid` — owned lists, lengths, and pool accounting
- `Scalar_Scheduler_Valid` — at most one Running task, identified by Current
- `Ready_Membership_Valid` — Ready state iff `Ready_Occurrences = 1`
- `All_Ready_Priorities_Valid` — every node under `Heads(P)` has priority P

SPARK ownership still proves unique writable node ownership, which is
distinct from Task_Id uniqueness. The latter is proved separately by
`Ready_Occurrences (S, T) <= 1`. Ordered FIFO sequences are not in the
occurrence model; tail insertion remains an implementation property.

Shared bounds are static: 16 tasks, 8 priorities, static identities,
no dynamic creation after initialization.

## Gold-level target

The intended proof target is SPARK Gold integrity, documented in
`docs/proof_strategy.md` as `REQ-SCHED-001` … `REQ-SCHED-008`. Examples
include "at most one Running task" and "ready-queue membership matches
Ready state".

Gold here means proved structural/integrity contracts. It does **not**
mean full functional correctness of the scheduler. The pointer
scheduler currently meets that Gold target. The indexed scheduler
meets its current local contracts, not yet Gold reachability.

## Layout

- `src/rtos.ads` — parent namespace
- `src/rtos-types.ads` — `Task_Id`, `Priority`, `Task_State`, optional IDs
- `src/rtos-pointer_scheduler.*` — owned singly linked ready lists
- `src/rtos-indexed_scheduler.*` — ID-linked ready lists
- `docs/architecture.md` — representation and ownership discussion
- `docs/proof_strategy.md` — integrity requirements and proof policy

## Build and proof

```
alr build
alr -n exec -- gnatprove -P spark_rtos_schedulers.gpr -U --mode=all --level=2 --timeout=0 --steps=10000000 --checks-as-errors=on --report=all --output=brief --output-header
```

The project uses GNATprove proof level 2 for ownership/framing checks. Current
counts are reported by each run rather than hardcoded here. See
[`docs/ci.md`](docs/ci.md) for the strict proof gate, downloadable evidence,
and local reproduction instructions.

The pointer scheduler meets the project's documented SPARK Gold
integrity target for REQ-SCHED-001 through REQ-SCHED-008. The indexed
scheduler's behavioral and local structural contracts are fully proved
for the current invariant; indexed Gold reachability, acyclicity, and
membership closure remain deferred. That is not a claim of full
functional correctness, Platinum, timing, fairness, or FIFO sequence
proof.

The build currently reports that the standard big-integer package is an
Ada 2022 unit under the existing compiler mode. Proof emits informational
messages for four statically unrolled ghost loops. The checked
`At_End_Borrow` annotation supports tail-append model invariants; it does
not suppress proof checks.
