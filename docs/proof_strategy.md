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

The pointer primitives prove mathematical length and content effects.
`Initialize` establishes `Representation_Valid` and
`Scalar_Scheduler_Valid`. `Make_Ready`, `Block`, `Select_Next`, `Yield`,
and `Schedule` require and preserve both, except that `Make_Ready` does
not yet claim the Running-implies-capacity slot: that still needs
uniqueness. Existing list-model contracts are retained.

| Requirement | Current status |
| --- | --- |
| REQ-SCHED-001 | Proved at the scalar Current/States layer via `Scalar_Scheduler_Valid`. Initialize, Make_Ready, Block, Select_Next, Yield, and Schedule establish or preserve it. |
| REQ-SCHED-002 | Partially proved. Running tasks are represented by Current and consume no ready node. Full list-membership exclusion still depends on uniqueness. |
| REQ-SCHED-003 | Partial. Ready-list nodes have valid task IDs; the state=Ready relationship still needs deep cross-model proof. |
| REQ-SCHED-004 | Partial. Make_Ready membership and occurrence increment are proved; Ready-state equivalence and uniqueness are deferred. |
| REQ-SCHED-005 | Not yet proved. SPARK ownership proves unique writable node ownership, not uniqueness of stored Task_Id values across distinct nodes. |
| REQ-SCHED-006 | Partial / not yet fully proved. Selection uses the highest nonempty ready head, but queue-priority consistency (node Id belongs to that priority) is not encoded. |
| REQ-SCHED-007 | Partially proved for the currently encoded representation and scalar invariants. Public pointer operations preserve `Representation_Valid` and `Scalar_Scheduler_Valid`. |
| REQ-SCHED-008 | Proved at the ready-head model level: Select_Next consumes the highest nonempty priority, and every strictly higher head is empty. |

Recursive ghost list models terminate structurally along owned `Next`
links. Unique writable node ownership and semantic list-content properties
are distinct: ownership excludes cycles/aliases but does not exclude two
nodes with equal task IDs. Occurrence maps preserve multiplicity, not order.
Tail insertion is therefore an implementation property pending ordered
ghost sequence modeling.

`Lemma_Free_Node_Available` proves that representation validity plus
`Ready_Nodes < Max_Tasks` implies a non-null free head. It has a checked
body and no assumptions. Yield and Schedule do not take a public
`Has_Free_Node` precondition. When Current identifies a Running task,
`Running_Has_Free_Slot` supplies the counter-level bound and the existing
lemma converts it to a free node.

The only GNATprove annotation remains `At_End_Borrow` on a ghost identity
function, for checked tail-traversal pledges. No proof-silencing
annotations are used. The scheduler is not claimed Gold-complete.

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
REQ-SCHED-001 is now encoded and proved at the scalar layer.
REQ-SCHED-008 is proved at the ready-head model. Remaining Gold
membership, uniqueness, and ordered-FIFO encodings are later work.
