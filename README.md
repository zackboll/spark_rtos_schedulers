# SPARK RTOS Schedulers

Educational SPARK models of a single-CPU fixed-priority preemptive
scheduler. This is a formal-verification experiment, **not** a
production RTOS: there is no context switch, interrupt handling, SMP,
mutex, or wait-queue implementation.

## Why two schedulers?

The same logical scheduler is being built twice:

1. `RTOS.Pointer_Scheduler` — per-priority singly linked ready lists
   using Ada access types and SPARK ownership/borrowing.
2. `RTOS.Indexed_Scheduler` — the same linked-queue behavior with
   bounded `Task_Id` links instead of pointers, aiming at O(1)
   enqueue, dequeue, and same-priority yield.

The question under investigation is architectural: SPARK's ownership
model allows only one mutable access path to a heap list. A
conventional `Head` plus persistent `Tail` pointer into the same list
is therefore not a legal SPARK design. The pointer model accepts O(N)
tail insertion via a temporary borrower. The indexed model keeps `Head`
and `Tail` because the links are IDs, not writable aliases.

## Current status

The pointer scheduler now implements the real behavioral transitions on
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
There is no allocation after `Initialize`. Indexed scheduler operations
remain representation-preserving skeletons.

`Scheduler_Valid` composes four proved predicates:

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
mean full functional correctness of the scheduler.

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
alr exec -- gnatprove -P spark_rtos_schedulers.gpr --mode=prove
```

The project uses GNATprove proof level 2 for ownership/framing checks.
All 643 checks pass (zero unproved or justified checks). All scheduler
units are analyzed in SPARK without suppressed checks or proof-silencing
annotations. The pointer scheduler now meets the project's documented
SPARK Gold integrity target for REQ-SCHED-001 through REQ-SCHED-008.
That is not a claim of full functional correctness, Platinum, timing,
fairness, or FIFO sequence proof.

The build currently reports that the standard big-integer package is an
Ada 2022 unit under the existing compiler mode. Proof emits informational
messages for four statically unrolled ghost loops. The checked
`At_End_Borrow` annotation supports tail-append model invariants; it does
not suppress proof checks.
