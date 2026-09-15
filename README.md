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

The pointer scheduler now has a proved ownership-safe linked-list core:
fixed free-node pool, O(1) acquire/release/head-remove, and O(N) tail
append via an anonymous access borrower. `Make_Ready` is real only in the
pointer scheduler. Its `Block`, `Yield`, `Select_Next`, and `Schedule`
are intentionally representation-preserving no-op skeletons. All indexed
queue operations (including `Make_Ready`) are likewise no-op skeletons;
`Initialize` remains real in both packages.

This temporary scaffolding prevents unfinished public operations from
creating states that already violate the future Gold invariants, such as
Ready state without queue membership or duplicate ready entries after
`Make_Ready`, `Block`, `Make_Ready`. Pointer `Block` leaves the task Ready,
so a second `Make_Ready` for that task still fails its precondition.
The next feature task will implement full pointer scheduler transitions.
The pointer ghost representation model now proves actual list lengths,
valid node IDs, occurrence preservation, and pool accounting. Behavioral
transitions and the remaining Gold state/membership invariants are deferred.
Indexed queues remain unimplemented.

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
All 253 checks pass (zero unproved or justified checks). All scheduler
units are analyzed in SPARK without suppressed checks or proof-silencing
annotations. This proves the current contracts, not the future Gold
scheduler invariants.

The build currently reports that the standard big-integer package is an
Ada 2022 unit under the existing compiler mode. Proof emits informational
messages for three statically unrolled ghost loops. The checked
`At_End_Borrow` annotation supports tail-append model invariants; it does
not suppress proof checks.
