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

The pointer scheduler now has a proved ownership-safe linked-list
core. Ready-queue *scheduler* semantics (block, yield, select) are still
skeletons; Gold integrity invariants are not yet attached.

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
by a local named `Node_Access` while it is being moved. `Make_Ready`
exercises acquire + tail-append. `Block`, `Yield`, `Select_Next`, and
`Schedule` remain representation-preserving no-op skeletons.
`Acquire_Node` calls `Remove_Ready_Head`;
`Release_Node` is proved independently but is not yet called by a public
operation. Counters are updated by `Make_Ready`, not the list primitives.

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
exists in `Dormant`. Only pointer `Make_Ready` currently changes this state.

Gold-level integrity properties for these structures are listed in
`docs/proof_strategy.md`. They are not yet attached as SPARK invariants.
The pointer package currently proves the ownership foundation (moves,
borrows, reborrows, and allocation-free list operations), not Gold
scheduler integrity.
