# Architecture

This repository is an educational SPARK experiment, not a production
RTOS. It compares two implementations of the same single-CPU
fixed-priority preemptive scheduler in order to show how SPARK
ownership rules affect ready-queue representation.

Both models share the assumptions in `RTOS.Types`:

- one CPU, no SMP
- 16 statically identified tasks
- 8 priority levels, with larger `Priority` values more urgent
- no mutexes, priority inheritance, interrupts, or wait queues
- no dynamic task creation after `Initialize`
- no machine context switching

The public operations are the same in both scheduler packages:

- `Initialize`
- `Make_Ready`
- `Block`
- `Yield`
- `Select_Next`
- `Schedule`

The pointer scheduler now implements the real behavioral transitions on
the proved ownership-safe linked-list core. Queue nodes represent READY
membership only. The running task occupies `Current` and owns no ready
node. The central invariant `Scheduler_Valid` composes representation,
scalar Current/Running, ready-membership uniqueness, and queue-priority
consistency. SPARK Gold integrity for REQ-SCHED-001 through REQ-SCHED-008
is discharged. Ordered FIFO remains deferred.

## The SPARK ownership question

A conventional C RTOS ready list often has both `Head` and `Tail`
pointers into the same mutable singly linked list, and may also point
from the list into a task-control-block table. SPARK's ownership model
does not allow that aliasing:

- every mutable heap cell has one owner
- a persistent second writable access path is illegal
- `'Access` / `Unchecked_Access` into an in-object TCB array is not an
  acceptable workaround

The two scheduler packages are the architectural response to that
constraint.

## Pointer scheduler

Package: `RTOS.Pointer_Scheduler`.

Each heap node is:

```
type Ready_Node is record
   Id   : Optional_Task_Id;  --  Ada reserves Task
   Next : Node_Access;
end record;
```

There are no parent/back pointers. A free node has `Id = No_Task`.
A ready node may hold a valid `Task_Id`.

`Initialize` allocates exactly `Max_Tasks` nodes and links them into
`Free_Head`. After that, enqueue, dequeue, acquire, and release never
allocate. The ownership roots are:

```
Free_Head -> Node -> Node -> ... -> Node
Heads (P) -> Node -> Node -> ... -> Node
```

A node is always on exactly one of those chains, or is temporarily owned
by a local named `Node_Access` while it is being moved. There is still no
persistent Tail, Current_Node, back pointer, parent pointer, or
task-table pointer.

Public pointer operations:

- `Make_Ready` acquires a free node and appends at the ready tail.
- `Block` marks the currently running task Blocked and clears Current.
  It does not remove an arbitrary ready node from the middle of a list.
- `Select_Next` scans the eight priorities from highest to lowest,
  removes the highest nonempty ready head, sets that task Running, and
  releases the detached node to `Free_Head`.
- `Yield` requeues Current at the tail of its own priority, then
  dispatches with `Select_Next`.
- `Schedule` dispatches when idle. If a task is already running, it
  preempts only when a strictly higher-priority ready head exists.
  Equal-priority tasks rotate only through Yield.

Priority lookup is O(P) with P=8 fixed. Tail insertion remains O(N)
because there is no stored Tail. `Acquire_Node` calls `Remove_Ready_Head`;
`Release_Node` is used by `Select_Next`. Counters are updated by the
public operations, not the list primitives. Accounting remains
`Free_Node_Count + Ready_Node_Count = Max_Tasks` at stable public
boundaries.

Initialization requires `Is_Virgin`, preventing overwrite of an existing
pool. Its private `Allocate_Pool` helper starts with a null local owner
and executes once per task (16 times):

```ada
Head := new Ready_Node'(Id => No_Task, Next => Head);
Count := Count + 1;
```

The old chain moves into the new node's `Next`; the new node becomes the
head. `Initialize` moves the completed chain into `S.Free_Head`, leaving
all ready heads null. This helper is called only by `Initialize`.

### Move

Named `Node_Access` values are unique owners. Assigning them transfers
ownership; the source is then moved-from and cannot be used as a second
writable path. Head removal and free-list acquire/release are O(1) moves:

```
Node := Head;       --  Head is moved-from
Head := Node.Next;  --  remainder stays with Head
Node.Next := null;  --  detached node owns only itself
```

### Borrow

Tail insertion does **not** store a persistent `Tail`. For a nonempty
list the walk is a nested anonymous mutable access:

```
Cursor : access Ready_Node := Head;
```

That declaration is a SPARK borrow. While `Cursor` exists, `Head` is
inaccessible through the owning path; the list is mutated only through
the borrower.

### Reborrow

Advancing the cursor goes strictly deeper into the already-borrowed
structure:

```
Cursor := Cursor.Next;
```

This is a reborrow, not a new owner. Termination is proved with:

```
pragma Loop_Variant (Structural => Cursor);
```

When the nested borrower scope ends, ownership returns to `Head`.

### Why there is no tail pointer

A persistent writable tail pointer would be a second mutable access path
into a structure already owned transitively by `Head`. SPARK forbids that
alias. The O(N) tail walk is therefore deliberate.

Pointer-operation complexity:

- acquire free node: O(1)
- release free node: O(1)
- remove ready head: O(1)
- append ready tail: O(N)
- round-robin yield: O(N) once wired

## Pointer verification model

The pointer package now has structurally recursive ghost observations over
`access constant Ready_Node`: `List_Length`, `All_Free`,
`All_Ready_Ids_Valid`, `Contains_Id`, and `Occurrences`. Lengths and
occurrences use mathematical `Big_Natural` values from the standard Ada
big-integer package (the installed `SPARK.Big_Integers` is its rename).
No runtime model fields or model allocations are introduced.

Structural recursion follows `Next`; ownership excludes cycles, while
GNATprove checks every structural termination obligation. Ownership proves
unique writable ownership of nodes, not uniqueness of stored task IDs.
The ghost content model proves per-ID occurrence preservation separately.
`Contents` is a ghost occurrence map, not an ordered sequence model.
Head-removal contracts preserve the remainder's length, occurrence map,
and free/valid-ID predicates; an ordered sequence model remains future work.

`Representation_Valid` ties the actual free-chain length to
`Free_Node_Count`, sums all eight ready-chain lengths into
`Ready_Node_Count`, requires their sum to be 16, and requires free IDs to
be `No_Task` and ready IDs to be valid. `Initialize` establishes it;
`Make_Ready`, `Block`, `Select_Next`, `Yield`, and `Schedule` preserve it.

A separate scalar predicate `Scalar_Scheduler_Valid` encodes REQ-SCHED-001:
`Current = No_Task` iff no task is Running, and if `Current = T` then
`State(T) = Running` and every other task is not Running. This is kept
logically distinct from pointer `Representation_Valid`.

Tail append retains the original anonymous borrower, reborrow, and
structural loop variant. Ghost loop invariants relate the eventual whole
list to the current suffix for length, occurrences, validity, and inserted
membership. The ghost identity function `At_End` uses GNATprove's
`At_End_Borrow` annotation to express these pledges. This is a checked
borrow-modeling annotation, not proof suppression or an assumption.

`Lemma_Free_Node_Available` derives a non-null free head from
representation validity and `Ready_Node_Count < Max_Tasks`. Yield and
Schedule do not take a public `Has_Free_Node` precondition. When Current
identifies a Running task, `Running_Has_Free_Slot` supplies the
counter-level bound, and the existing lemma converts it to a free node.

SPARK ownership proves unique writable node ownership. Semantic Task_Id
uniqueness is a different property, proved by `Ready_Membership_Valid`:
`Ready_Occurrences (S, T)` is 1 if `State(T) = Ready` and 0 otherwise.
That excludes duplicates within one list and the same identity under two
heads. Ordered FIFO remains an implementation property of tail insertion
pending an ordered ghost sequence model.

## Indexed scheduler

Package: `RTOS.Indexed_Scheduler`.

The indexed scheduler now implements the same public behavioral
operations as the pointer scheduler. `Task_Id` itself is the logical
queue node. There is no separate heap node and no free-node pool.
`Heads`, `Tails`, and `Next` store `Optional_Task_Id` values:

```
Heads(P)
   |
   v
Task_Id -> Task_Id -> Task_Id -> No_Task
                     ^
                     |
                  Tails(P)
```

`Next` is indexed by `Task_Id`. Persistent Head and Tail are legal
because integer IDs are not SPARK access aliases. There is no
allocation and no access type in this package.

Public operations:

- `Make_Ready`: Dormant/Blocked -> Ready, O(1) append to the
  configured-priority tail, `Ready_Count + 1`.
- `Select_Next`: find the highest `Nonempty` priority (at most 8
  checks), O(1) dequeue of that head, Ready -> Running, set Current,
  `Ready_Count - 1`. If no ready queue is nonempty, remain idle.
- `Block`: current Running -> Blocked, Current := `No_Task`, queue
  unchanged.
- `Yield`: current Running -> Ready, O(1) tail enqueue, then
  `Select_Next`.
- `Schedule`: dispatch when idle. Equal priority does not preempt. A
  strictly higher ready priority causes the current task to be O(1)
  requeued, followed by `Select_Next`.

Indexed complexity, with `Priority_Count` statically equal to 8:

- enqueue                    O(1)
- dequeue                    O(1)
- yield queue mutation       O(1)
- preemption queue mutation  O(1)
- priority selection         at most 8 `Nonempty` checks

Selection is therefore constant with respect to task count. The package
does not implement or claim a ready-priority bitmap or a CLZ/bit-scan
selector.

### Indexed behavioral proof model

`Indexed_Scheduler_Valid` is a local behavioral/structural layer. It
does not prove complete Head-chain reachability, global acyclicity, or
Ready-iff-reachable membership. Those remain the next indexed Gold
layer.

#### Queue_Structure_Valid

For each priority:

- Head empty iff Tail empty
- `Nonempty` matches Head presence
- Tail.Next = `No_Task`

This is endpoint/flag consistency, not a walk of the whole chain.

#### Endpoint_Ready_Valid

Existing Head/Tail IDs:

- have state Ready
- have configured priority matching P

#### Next_Edges_Valid

Every non-null immediate Next target:

- is Ready
- has the same configured priority as its source

This is a one-edge invariant. It supplies Dequeue with successor
state/priority without reachability.

#### Heads_Unreferenced

No Next edge points to a current Head. In particular, a selected head
has no incoming edge, including no self-loop as head. This is the
predecessor discipline needed by Dequeue.

#### Next_Injective

Two non-null equal Next targets must have the same source. This
prevents two different tasks from sharing an immediate successor. When
Dequeue promotes a successor to Head and clears the old head's Next,
the successor has no remaining predecessor.

`Next_Injective` is local predecessor uniqueness. It does **not** prove
global acyclicity, global membership uniqueness, or reachability from
a Head.

#### Nonready_Unlinked

A non-Ready task has no outgoing Next. Combined with `Next_Edges_Valid`,
a non-Ready task also cannot currently be the target of any Next edge,
because every non-null target must be Ready.

#### Ready_Count_State_Valid

`Ready_Count` equals the number of tasks whose scalar state is Ready.
This proves count increments/decrements and Select_Next subtraction
safety. It does **not** prove that `Ready_Count` equals the total
length of all Head/Next chains. Disconnected Ready components remain
admitted by this behavioral invariant.

`No_Self_Loops` exists as a ghost observation but is not part of the
stable invariant. `Heads_Unreferenced` already excludes self-loops for
current heads. Global acyclicity of disconnected/non-head nodes belongs
to the later Gold reachability model.

### Pointer vs indexed proof difference

This contrast is one of the primary purposes of the repository.

Pointer scheduler:

- access-based nodes
- SPARK ownership controls writable aliasing
- structural ownership prevents pointer cycles in owned list structures
- no persistent writable Tail
- O(N) tail append through anonymous borrowing/reborrowing
- semantic Task_Id uniqueness still requires ghost occurrence modeling

Indexed scheduler:

- Task_Id links
- no writable-pointer aliasing problem
- persistent Head/Tail
- O(1) tail append
- ownership no longer provides structural graph properties
- predecessor discipline must be encoded explicitly
  (`Heads_Unreferenced`, `Next_Injective`, `Next_Edges_Valid`)
- global reachability/acyclicity will have to be proved semantically

## Shared package shape

Both packages expose a limited private `Scheduler` object rather than
hidden package state. That keeps the comparison aligned and gives the
pointer model a single owner for its heap lists. Scheduler objects are
initialized with a complete `Task_Priorities` map; every `Task_Id` then
exists in `Dormant`. Pointer and indexed `Make_Ready`, `Block`,
`Select_Next`, `Yield`, and `Schedule` now change this state.

Gold-level integrity properties for these structures are listed in
`docs/proof_strategy.md`. The pointer package now proves the ownership
foundation, the scalar Current/Running invariant, ready-membership
uniqueness via `Ready_Occurrences`, queue-priority consistency, and
highest-configured-priority selection. It meets the project's SPARK Gold
integrity target. Ordered FIFO/round-robin sequence proof remains deferred.

The indexed package proves the corresponding public operations against
its local structural invariant. It does not yet prove indexed Gold
reachability or membership closure.
