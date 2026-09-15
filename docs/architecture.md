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
node. Gold completion is still partial: scalar Current/Running is proved,
but Task_Id uniqueness and ordered FIFO remain deferred.

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
That slot is a capacity fact, not a uniqueness proof: SPARK ownership
still does not prove that two distinct nodes cannot store the same
`Task_Id`. Ordered FIFO remains an implementation property of tail
insertion pending an ordered ghost sequence model.

## Indexed scheduler

Package: `RTOS.Indexed_Scheduler`.

Only `Initialize` is real. `Make_Ready`, `Block`, `Yield`, `Select_Next`,
and `Schedule` are temporary representation-preserving no-ops; they do
not change task states or queue links.

This representation keeps linked-queue behavior but does not use Ada
access types for queue membership. `Head`, `Tail`, and `Next` contain
`Optional_Task_Id` values:

```
Head(P) -> Task_Id -> Task_Id -> Task_Id
                              ^
                              |
                            Tail(P)
```

Because the links are identifiers rather than writable pointers, `Head`
and `Tail` do not create SPARK ownership aliases. That is expected to
permit:

- enqueue: O(1)
- dequeue: O(1)
- same-priority yield: O(1)

Task selection may later use a fixed-width ready-priority bitmap over
the eight priority levels. The indexed lists still encode the same
scheduler semantics as the pointer lists; only the representation, and
therefore the aliasing structure, changes.

## Shared skeleton shape

Both packages expose a limited private `Scheduler` object rather than
hidden package state. That keeps the comparison aligned and gives the
pointer model a single owner for its heap lists. Scheduler objects are
initialized with a complete `Task_Priorities` map; every `Task_Id` then
exists in `Dormant`. Pointer `Make_Ready`, `Block`, `Select_Next`,
`Yield`, and `Schedule` now change this state. Indexed operations other
than `Initialize` remain no-ops.

Gold-level integrity properties for these structures are listed in
`docs/proof_strategy.md`. The pointer package now proves the ownership
foundation plus the scalar Current/Running invariant and highest-priority
ready-head selection. It is not Gold-complete: uniqueness, Ready-state
cross-model membership, and ordered FIFO remain deferred.
