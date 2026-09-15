# Proof Strategy

The initial verification target is SPARK **Gold**: integrity properties
of scheduler state, not complete functional correctness of dispatching.

Gold means that key safety and structural invariants are expressed as
SPARK contracts and proved. It does **not** mean that the scheduler is
fully specified or that every scheduling decision is proved equivalent
to an abstract functional model. Platinum-style functional completeness
is outside the initial scope.

The repository currently aims for a clean SPARK-eligible architecture:
absence of hidden proof failures, with the integrity requirements below
documented as stable IDs. They are encoded as predicates and contracts
on the pointer scheduler and are claimed proved only when the
corresponding VCs discharge. The indexed scheduler has a separate
proved behavioral/local structural layer; it does not yet claim Gold
reachability.

## Integrity requirements

### Current Gold integrity layer

The pointer primitives prove mathematical length and content effects.
`Initialize` establishes `Scheduler_Valid`. `Make_Ready`, `Block`,
`Select_Next`, `Yield`, and `Schedule` require and preserve it.
`Scheduler_Valid` composes:

- `Representation_Valid`
- `Scalar_Scheduler_Valid`
- `Ready_Membership_Valid`
- `All_Ready_Priorities_Valid`

| Requirement | Formalization | Preserved by | Status | Deliberately excluded |
| --- | --- | --- | --- | --- |
| REQ-SCHED-001 | `Scalar_Scheduler_Valid`: `Current = No_Task` iff no task is Running; `Current = T` implies `State(T) = Running` and every other task is not Running. Implied by `Scheduler_Valid`. | Initialize establishes; Make_Ready, Block, Select_Next, Yield, Schedule preserve | Proved | Full functional dispatch automaton |
| REQ-SCHED-002 | `Ready_Membership_Valid` plus `Scalar_Scheduler_Valid`: Running implies `Ready_Occurrences (S, T) = 0` | Same public operations | Proved | Architectural "Current has no Node_Access" is not the proof; occurrence count is |
| REQ-SCHED-003 | `Ready_Membership_Valid`: `Ready_Occurrences (S, T) > 0` implies `State(T) = Ready`. Ready nodes also satisfy `All_Ready_Ids_Valid` | Same public operations | Proved | Ordered position of the Ready node |
| REQ-SCHED-004 | `Ready_Membership_Valid`: `State(T) = Ready` implies `Ready_Occurrences (S, T) = 1` globally across all eight heads | Same public operations | Proved | Which physical node holds T |
| REQ-SCHED-005 | Derived from `Ready_Membership_Valid`: `Ready_Occurrences (S, T) <= 1` for every T. Excludes duplicates in one list and the same Id under two heads | Same public operations | Proved | SPARK unique node ownership, which is a different property |
| REQ-SCHED-006 | `All_At_Priority` / `All_Ready_Priorities_Valid`: a node under `Heads(P)` has `Priorities(Id) = P`. `Lemma_Occurrence_Implies_Priority` and `Lemma_Ready_Task_At_Configured_Priority` connect occurrences to configured priority | Initialize (empty heads); Make_Ready / Yield / Schedule append only at `S.Priorities(Id)`; Select_Next preserves remaining heads; Block leaves lists unchanged | Proved | FIFO order inside a priority |
| REQ-SCHED-007 | Public contracts: Initialize posts `Scheduler_Valid`; Make_Ready, Block, Yield, Select_Next, Schedule require and post `Scheduler_Valid` | All public pointer operations | Proved | Indexed scheduler; complete scheduling traces |
| REQ-SCHED-008 | `Find_Highest_Ready` plus `Lemma_Highest_Ready_Is_Greatest_Priority`: selected task's configured priority is greatest among Ready tasks, because Ready implies occurrence 1 under that configured head | Select_Next, and Schedule/Yield via Select_Next | Proved | Fairness, timing, POSIX/Ada dispatching completeness |

Recursive ghost list models terminate structurally along owned `Next`
links. Unique writable node ownership and semantic list-content properties
are distinct: ownership excludes cycles/aliases but does not exclude two
nodes with equal task IDs. `Ready_Membership_Valid` is the semantic
uniqueness proof, using occurrence counts rather than ownership.

Occurrence maps preserve multiplicity, not order. Tail insertion is
therefore an implementation property pending ordered ghost sequence
modeling. FIFO/round-robin sequence proof is not required for Gold.

`Lemma_Free_Node_Available` proves that representation validity plus
`Ready_Nodes < Max_Tasks` implies a non-null free head. It has a checked
body and no assumptions. Yield and Schedule do not take a public
`Has_Free_Node` precondition. When Current identifies a Running task,
`Running_Has_Free_Slot` supplies the counter-level bound and the existing
lemma converts it to a free node.

The only GNATprove annotation remains `At_End_Borrow` on a ghost identity
function, for checked tail-traversal pledges. No proof-silencing
annotations are used. The pointer scheduler meets the project's SPARK
Gold integrity target. That is not Platinum, full functional correctness,
timing correctness, fairness, or FIFO proof.

### REQ-SCHED-001

At most one task is Running.

The `Current` slot, together with per-task `Task_State` values, must
never identify two Running tasks. If a task is Running, it is the
current task; if no task is current, no task is Running.

### REQ-SCHED-002

A Running task is not present in a ready queue.

The running task occupies the processor, not a ready list. Queue
membership and Running are mutually exclusive.

### REQ-SCHED-003

Every task present in a ready queue has state Ready.

Ready-list nodes or indexed links are not allowed to refer to Dormant,
Running, or Blocked tasks.

### REQ-SCHED-004

A Ready task occurs in exactly one ready queue.

State Ready is equivalent to membership in one priority queue. A Ready
task is never absent from the queues and never present in two of them.

### REQ-SCHED-005

No task appears more than once in the ready structures.

Ready lists contain unique `Task_Id` values. Cycles, repeated nodes,
and the same identity in two priorities are all forbidden.

### REQ-SCHED-006

Every task in a priority queue belongs to that priority.

If a task is linked under `Heads (P)` (pointer model) or the indexed
list for `P`, its stored priority is `P`.

### REQ-SCHED-007

Scheduler operations preserve scheduler structural invariants.

`Initialize` establishes the invariants. `Make_Ready`, `Block`,
`Yield`, `Select_Next`, and `Schedule` preserve them. This is the
Gold-level framing property over the representation, not a complete
trace specification of scheduling.

### REQ-SCHED-008

`Select_Next` eventually must select a task from the highest nonempty
priority.

When at least one ready queue is nonempty, the selected task belongs to
the maximum `Priority` that currently has a ready member. This is an
integrity constraint on choice among ready queues, not a full proof
that the scheduler implements every detail of POSIX or Ada dispatching.

## Indexed scheduler — current behavioral proof layer

This section is **not** indexed Gold completion. The pointer Gold table
above remains the project's Gold integrity claim. The indexed scheduler
currently proves a local behavioral/structural invariant:

`Indexed_Scheduler_Valid` =
`Indexed_Representation_Valid` +
`Scalar_Scheduler_Valid` +
`Ready_Count_State_Valid`

where `Indexed_Representation_Valid` composes
`Queue_Structure_Valid`, `Endpoint_Ready_Valid`,
`Nonready_Unlinked`, `Next_Edges_Valid`, `Heads_Unreferenced`, and
`Next_Injective`.

| Property | Indexed formalization | Current status |
| --- | --- | --- |
| Current/Running uniqueness | `Scalar_Scheduler_Valid` | Proved |
| endpoint Head/Tail consistency | `Queue_Structure_Valid` | Proved |
| endpoint state/priority | `Endpoint_Ready_Valid` | Proved |
| non-Ready tasks have no outgoing link | `Nonready_Unlinked` | Proved |
| immediate Next targets valid | `Next_Edges_Valid` | Proved |
| Heads have no predecessor | `Heads_Unreferenced` | Proved |
| unique immediate predecessor | `Next_Injective` | Proved |
| Ready_Count equals scalar Ready-state count | `Ready_Count_State_Valid` | Proved |
| highest Nonempty priority selection | `Find_Highest_Ready` / contracts | Proved |
| complete Head reachability | future Gold model | Deferred |
| global acyclicity | future Gold model | Deferred |
| Ready iff reachable exactly once | future Gold model | Deferred |
| tail reachable from head | future Gold model | Deferred |
| chain cardinality = Ready_Count | future Gold model | Deferred |

`Ready_Count_State_Valid` counts scalar Ready states. It does not prove
queue-chain cardinality. `Next_Injective` proves unique non-null
immediate predecessors. It does not prove global acyclicity or
membership uniqueness. Disconnected Ready components remain admitted.

### Indexed requirement status

These statuses are conservative. They describe the current local layer,
not Gold closure.

| Requirement | Indexed status | Justification |
| --- | --- | --- |
| REQ-SCHED-001 | Proved at the scalar Current/Running layer | `Scalar_Scheduler_Valid` is part of `Indexed_Scheduler_Valid` and is preserved by Initialize, Make_Ready, Block, Yield, Select_Next, and Schedule |
| REQ-SCHED-002 | Partial / local | The Running task has no outgoing Next (`Nonready_Unlinked`) and Current is unique, but complete absence from every reachable ready chain is not yet globally modeled |
| REQ-SCHED-003 | Partial | Endpoints and every immediate Next target are Ready (`Endpoint_Ready_Valid`, `Next_Edges_Valid`), but complete Head-reachable chain closure is not yet formalized globally |
| REQ-SCHED-004 | Not yet fully proved | Ready scalar state is counted (`Ready_Count_State_Valid`), but Ready => reachable exactly once from one Head is deferred |
| REQ-SCHED-005 | Partial | `Next_Injective` provides unique immediate predecessors, but global acyclicity, repetition, and membership uniqueness are deferred |
| REQ-SCHED-006 | Partial | Endpoints and Next edges preserve configured priority locally; the full reachable-chain property is deferred |
| REQ-SCHED-007 | Proved for the current local representation invariant | Public indexed operations require and preserve `Indexed_Scheduler_Valid`. This is not yet the eventual Gold reachability invariant |
| REQ-SCHED-008 | Proved at the Nonempty/head selection layer | `Find_Highest_Ready` selects the greatest nonempty priority. Full equivalence to the greatest-priority Ready task depends on Ready => globally reachable queue membership, so Gold-level closure remains deferred |

Deferred to indexed Gold reachability, and not claimed here:

- recursive/bounded Head reachability
- complete acyclicity
- Ready iff reachable
- exact queue-chain length = Ready_Count
- tail reachability
- global queue membership uniqueness
- indexed REQ-SCHED-003..006 Gold closure


## What Gold is not

These requirements constrain well-formedness of scheduler state and the
priority of the chosen task. They do not, by themselves, prove:

- fairness beyond the intended round-robin yield
- timing properties
- interrupt or device semantics
- equivalence to a mathematical scheduler automaton

Do not treat a future Gold result as a claim of full functional
correctness.

## SPARK policy

All scheduler logic is intended to remain in `SPARK_Mode => On`.

The following are out of bounds:

- `Unchecked_Access`
- unchecked conversion
- address arithmetic and `System.Address`
- suppressed checks
- raw allocation tricks
- `pragma Annotate` used only to silence proof failures
- weakened contracts used only to obtain a green proof

Contracts should be strengthened as the queue algorithms are
introduced, not relaxed around them.

## Initial proof workflow

Proof settings are deliberately unoptimized.

```
alr build
alr exec -- gnatprove -P spark_rtos_schedulers.gpr --mode=prove
```

The current whole-project GNATprove run discharges 894/894 checks
(zero unproved, zero justified, zero flow errors). REQ-SCHED-001
through REQ-SCHED-008 are encoded and proved on the pointer scheduler.
The indexed scheduler's current local contracts are also fully proved;
indexed Gold reachability remains later work. FIFO/round-robin sequence
ordering remains later work and is outside Gold.
