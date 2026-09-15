# Proof Strategy

The initial verification target is SPARK **Gold**: integrity properties
of scheduler state, not complete functional correctness of dispatching.

Gold means that key safety and structural invariants are expressed as
SPARK contracts and proved. It does **not** mean that the scheduler is
fully specified or that every scheduling decision is proved equivalent
to an abstract functional model. Platinum-style functional completeness
is outside the initial scope.

The skeleton currently aims only for a clean SPARK-eligible
architecture: absence of hidden proof failures, with the integrity
requirements below documented as stable IDs. Those requirements will
later become predicates, type invariants, preconditions, and
postconditions. They are not weakened, and they are not claimed proved,
until the corresponding queue implementations exist.

## Integrity requirements

### Current representation-model proof layer

The pointer primitives now prove mathematical length and content effects.
`Initialize` establishes `Representation_Valid`; `Make_Ready` requires and
preserves it, proves inserted membership and an occurrence increment,
and connects both counter updates to actual chain lengths. Existing
preconditions and counter postconditions are retained. Skeleton operations
preserve representation validity and remain behaviorally unimplemented.

| Requirement | Current status |
| --- | --- |
| REQ-SCHED-001 | Not yet encoded as a scalar running/current invariant |
| REQ-SCHED-002 | Not yet encoded as running/list exclusion |
| REQ-SCHED-003 | Partial: ready-node IDs valid; Ready-state relation deferred |
| REQ-SCHED-004 | Partial: Make_Ready membership and occurrence increment proved; equivalence deferred |
| REQ-SCHED-005 | Partial: node ownership proved; task-ID uniqueness deferred |
| REQ-SCHED-006 | Not yet encoded: task priority versus containing queue |
| REQ-SCHED-007 | Partial: pointer representation/accounting established and preserved |
| REQ-SCHED-008 | Not yet encoded: selection remains a skeleton |

Recursive ghost list models terminate structurally along owned `Next`
links. Unique writable node ownership and semantic list-content properties
are distinct: ownership excludes cycles/aliases but does not exclude two
nodes with equal task IDs. Occurrence maps preserve multiplicity, not order.

`Lemma_Free_Node_Available` proves that representation validity plus
`Ready_Nodes < Max_Tasks` implies a non-null free head. It has a checked
body and no assumptions. The stronger Running-implies-capacity result
needs the state/membership/uniqueness layer; no artificial Yield capacity
precondition has been introduced.

The only new GNATprove annotation is `At_End_Borrow` on a ghost identity
function, for checked tail-traversal pledges. No proof-silencing annotations
are used. Full scheduler behavior and full Gold completion remain deferred.

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

The skeleton is successful when GNATprove analyzes every intended
package as SPARK and reports no hidden or unexpected failed checks.
Queue-algorithm proofs, and the encoding of REQ-SCHED-001 through
REQ-SCHED-008 as proved contracts, are later work.
