with RTOS.Types;
with Ada.Numerics.Big_Numbers.Big_Integers;

--  Pointer-based fixed-priority scheduler.
--
--  Ownership roots after Initialize:
--
--    Free_Head -> Node -> Node -> ... -> Node
--    Heads (P) -> Node -> Node -> ... -> Node
--
--  Each heap node is reachable from exactly one of those roots, or is
--  temporarily owned by a local named access value during a move.
--  There is no persistent Tail access into a ready list.
--
--  Pointer operations:
--    acquire free node     O(1)
--    release free node     O(1)
--    remove ready head     O(1)
--    append ready tail     O(N)   --  intentional; no stored tail
--
--  Make_Ready acquires a free node and appends at the ready tail.
--  Select_Next consumes the highest-priority ready head and releases
--  that node to the free list. Block marks the current Running task
--  Blocked without touching lists. Yield requeues Current at its tail
--  then dispatches. Schedule preempts only for a strictly higher
--  nonempty ready priority.

package RTOS.Pointer_Scheduler
  with SPARK_Mode => On
is

   pragma Unevaluated_Use_Of_Old (Allow);

   use RTOS.Types;
   use Ada.Numerics.Big_Numbers.Big_Integers;

   subtype Node_Count is Natural range 0 .. Max_Tasks;

   type Ready_Length_Map is array (Priority) of Big_Natural;
   type Ready_Occurrence_Map is array (Task_Id) of Big_Natural;

   type Scheduler is limited private
     with Default_Initial_Condition =>
       Is_Virgin (Scheduler);

   function Is_Initialized (S : Scheduler) return Boolean
     with Ghost;

   --  Default-initialized object: no heap nodes and not started.
   --  Initialize may be called only in this state.
   function Is_Virgin (S : Scheduler) return Boolean
     with Ghost;

   function Current_Task (S : Scheduler) return Optional_Task_Id
   with
     Pre => Is_Initialized (S);

   function State_Of (S : Scheduler; Id : Task_Id) return Task_State
   with
     Pre => Is_Initialized (S);

   function Priority_Of (S : Scheduler; Id : Task_Id) return Priority
   with
     Pre => Is_Initialized (S);

   function Has_Free_Node (S : Scheduler) return Boolean
     with Ghost;

   function Free_Nodes (S : Scheduler) return Node_Count
     with Ghost;

   function Ready_Nodes (S : Scheduler) return Node_Count
     with Ghost;

   function Representation_Valid (S : Scheduler) return Boolean with Ghost;
   function Scalar_Scheduler_Valid (S : Scheduler) return Boolean with Ghost;
   function Ready_Membership_Valid (S : Scheduler) return Boolean with Ghost;
   function All_Ready_Priorities_Valid (S : Scheduler) return Boolean
     with Ghost;
   function Scheduler_Valid (S : Scheduler) return Boolean with Ghost;
   --  A Running task occupies Current and therefore leaves at least one
   --  pool node off the ready lists. Distinct from Has_Free_Node: this
   --  is the counter-level slot, later converted by the free-node lemma.
   function Running_Has_Free_Slot (S : Scheduler) return Boolean with Ghost;
   function Total_Ready_List_Length (S : Scheduler) return Big_Natural
     with Ghost;
   function Ready_Contains (S : Scheduler; Id : Task_Id) return Boolean
     with Ghost;
   function Ready_Occurrences (S : Scheduler; Id : Task_Id)
     return Big_Natural with Ghost;
   function Ready_List_Length (S : Scheduler; P : Priority) return Big_Natural
     with Ghost;
   function Free_List_Length (S : Scheduler) return Big_Natural with Ghost;
   function Copy_States (S : Scheduler) return Task_State_Map with Ghost;
   function Copy_Ready_Lengths (S : Scheduler) return Ready_Length_Map
     with Ghost;
   function Copy_Ready_Occurrences (S : Scheduler)
     return Ready_Occurrence_Map
   with Ghost,
     Post => (for all T in Task_Id =>
                Copy_Ready_Occurrences'Result (T) =
                  Ready_Occurrences (S, T));
   function No_Ready_Above
     (Lengths : Ready_Length_Map; Bound : Priority) return Boolean
     with Ghost;

   procedure Lemma_Free_Node_Available (S : Scheduler)
   with Ghost,
     Pre => Representation_Valid (S) and then Ready_Nodes (S) < Max_Tasks,
     Post => Has_Free_Node (S);

   --  Allocate the fixed pool of Max_Tasks nodes and build the free
   --  list. Initialization is allowed only once; there is no
   --  deallocation/reinitialization protocol.
   procedure Initialize
     (S          : in out Scheduler;
      Priorities : Task_Priorities)
   with
     Pre  => Is_Virgin (S),
     Post => Is_Initialized (S)
     and then Current_Task (S) = No_Task
     and then Has_Free_Node (S)
     and then Free_Nodes (S) = Max_Tasks
     and then Ready_Nodes (S) = 0
     and then (for all Id in Task_Id => State_Of (S, Id) = Dormant)
     and then Scheduler_Valid (S)
     and then Running_Has_Free_Slot (S);

   --  Acquire a free node, assign Id, and append at the tail of the
   --  ready list for Id's priority. No allocation is performed.
   procedure Make_Ready (S : in out Scheduler; Id : Task_Id)
   with
     Pre  => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then State_Of (S, Id) /= Ready
     and then State_Of (S, Id) /= Running
     and then Has_Free_Node (S)
     and then Free_Nodes (S) > 0
     and then Ready_Nodes (S) < Max_Tasks,
     Post => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then State_Of (S, Id) = Ready
     and then Free_Nodes (S) = Free_Nodes (S)'Old - 1
     and then Ready_Nodes (S) = Ready_Nodes (S)'Old + 1
     and then Ready_Contains (S, Id)
     and then Ready_Occurrences (S, Id) = To_Big_Integer (1)
     and then Ready_Occurrences (S, Id) = Ready_Occurrences (S, Id)'Old + 1
     and then Total_Ready_List_Length (S) =
                Total_Ready_List_Length (S)'Old + 1
     and then Free_List_Length (S) = Free_List_Length (S)'Old - 1
     and then Current_Task (S) = Current_Task (S)'Old
     and then (for all Other in Task_Id =>
                 (if Other /= Id then
                    State_Of (S, Other) = Copy_States (S)'Old (Other)
                    and then Ready_Occurrences (S, Other) =
                               Copy_Ready_Occurrences (S)'Old (Other)));

   --  Block the currently running task. Queue nodes represent READY
   --  membership only, so this transition does not touch any list.
   procedure Block (S : in out Scheduler; Id : Task_Id)
   with
     Pre  => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then Running_Has_Free_Slot (S)
     and then Current_Task (S) = To_Optional (Id)
     and then State_Of (S, Id) = Running,
     Post => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then Running_Has_Free_Slot (S)
     and then Current_Task (S) = No_Task
     and then State_Of (S, Id) = Blocked
     and then Ready_Occurrences (S, Id) = To_Big_Integer (0)
     and then Ready_Nodes (S) = Ready_Nodes (S)'Old
     and then Free_Nodes (S) = Free_Nodes (S)'Old
     and then Total_Ready_List_Length (S) =
                Total_Ready_List_Length (S)'Old
     and then Free_List_Length (S) = Free_List_Length (S)'Old
     and then (for all P in Priority =>
                 Ready_List_Length (S, P) =
                   Copy_Ready_Lengths (S)'Old (P))
     and then (for all Other in Task_Id =>
                 Ready_Occurrences (S, Other) =
                   Copy_Ready_Occurrences (S)'Old (Other))
     and then (for all Other in Task_Id =>
                 (if Other /= Id then
                    State_Of (S, Other) = Copy_States (S)'Old (Other)))
     and then (for all Other in Task_Id => State_Of (S, Other) /= Running);

   --  Requeue the running task at the tail of its priority list, then
   --  dispatch with Select_Next. Equal-priority rotation is an
   --  implementation property of tail insertion; the occurrence model
   --  does not yet prove ordered FIFO sequences.
   procedure Yield (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then Running_Has_Free_Slot (S)
     and then Has_Task (Current_Task (S))
     and then State_Of (S, To_Task_Id (Current_Task (S))) = Running,
     Post => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then Running_Has_Free_Slot (S)
     and then Has_Task (Current_Task (S))
     and then State_Of (S, To_Task_Id (Current_Task (S))) = Running
     and then Ready_Occurrences (S, To_Task_Id (Current_Task (S))) =
                To_Big_Integer (0)
     and then Ready_Nodes (S) = Ready_Nodes (S)'Old
     and then Free_Nodes (S) = Free_Nodes (S)'Old
     and then Total_Ready_List_Length (S) =
                Total_Ready_List_Length (S)'Old
     and then Free_List_Length (S) = Free_List_Length (S)'Old
     and then (if Current_Task (S) /= Current_Task (S)'Old then
                 State_Of (S, To_Task_Id (Current_Task (S)'Old)) = Ready)
     and then (for all Other in Task_Id =>
                 (if Other /= To_Task_Id (Current_Task (S)'Old)
                    and then Other /= To_Task_Id (Current_Task (S))
                  then State_Of (S, Other) = Copy_States (S)'Old (Other)));

   --  Dispatch the highest-priority ready head, or remain idle.
   --  Queue nodes represent READY membership only; the selected task
   --  occupies Current and consumes no ready node.
   procedure Select_Next (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then Running_Has_Free_Slot (S)
     and then Current_Task (S) = No_Task,
     Post => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then Running_Has_Free_Slot (S)
     and then (if Ready_Nodes (S)'Old = 0 then
        Current_Task (S) = No_Task
        and then Ready_Nodes (S) = Ready_Nodes (S)'Old
        and then Free_Nodes (S) = Free_Nodes (S)'Old
        and then Total_Ready_List_Length (S) =
                   Total_Ready_List_Length (S)'Old
        and then Free_List_Length (S) = Free_List_Length (S)'Old
        and then (for all Id in Task_Id =>
                    State_Of (S, Id) = Copy_States (S)'Old (Id))
        and then (for all P in Priority =>
                    Ready_List_Length (S, P) =
                      Copy_Ready_Lengths (S)'Old (P))
      else
        Has_Task (Current_Task (S))
        and then State_Of (S, To_Task_Id (Current_Task (S))) = Running
        and then Ready_Occurrences (S, To_Task_Id (Current_Task (S))) =
                   To_Big_Integer (0)
        and then Ready_Nodes (S) = Ready_Nodes (S)'Old - 1
        and then Free_Nodes (S) = Free_Nodes (S)'Old + 1
        and then Total_Ready_List_Length (S) =
                   Total_Ready_List_Length (S)'Old - 1
        and then Free_List_Length (S) = Free_List_Length (S)'Old + 1
        and then (for some P in Priority =>
                    Copy_Ready_Lengths (S)'Old (P) > 0
                    and then Ready_List_Length (S, P) =
                               Copy_Ready_Lengths (S)'Old (P) - 1
                    and then Priority_Of
                               (S, To_Task_Id (Current_Task (S))) = P
                    and then (for all Q in Priority =>
                                (if Q > P then
                                   Copy_Ready_Lengths (S)'Old (Q) = 0)
                                and then
                                (if Q /= P then
                                   Ready_List_Length (S, Q) =
                                     Copy_Ready_Lengths (S)'Old (Q))))
        and then (for all Other in Task_Id =>
                    (if Other /= To_Task_Id (Current_Task (S)) then
                       State_Of (S, Other) = Copy_States (S)'Old (Other))));

   --  Idle: dispatch with Select_Next. Running: preempt only when a
   --  strictly higher-priority ready head exists. Equal priority does
   --  not preempt; those tasks rotate only through Yield.
   procedure Schedule (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then Running_Has_Free_Slot (S),
     Post => Is_Initialized (S)
     and then Scheduler_Valid (S)
     and then Running_Has_Free_Slot (S)
     and then (if Has_Task (Current_Task (S)) then
                 State_Of (S, To_Task_Id (Current_Task (S))) = Running
                 and then Ready_Occurrences
                            (S, To_Task_Id (Current_Task (S))) =
                              To_Big_Integer (0)),
     Contract_Cases =>
       (Current_Task (S) = No_Task and then Ready_Nodes (S) = 0 =>
          Current_Task (S) = No_Task
          and then Ready_Nodes (S) = Ready_Nodes (S)'Old
          and then Free_Nodes (S) = Free_Nodes (S)'Old
          and then (for all Id in Task_Id =>
                      State_Of (S, Id) = Copy_States (S)'Old (Id)),
        Current_Task (S) = No_Task and then Ready_Nodes (S) > 0 =>
          Has_Task (Current_Task (S))
          and then Ready_Nodes (S) = Ready_Nodes (S)'Old - 1
          and then Free_Nodes (S) = Free_Nodes (S)'Old + 1,
        Has_Task (Current_Task (S))
          and then No_Ready_Above
                     (Copy_Ready_Lengths (S),
                      Priority_Of (S, To_Task_Id (Current_Task (S)))) =>
          Current_Task (S) = Current_Task (S)'Old
          and then Ready_Nodes (S) = Ready_Nodes (S)'Old
          and then Free_Nodes (S) = Free_Nodes (S)'Old
          and then (for all Id in Task_Id =>
                      State_Of (S, Id) = Copy_States (S)'Old (Id)),
        others =>
          Has_Task (Current_Task (S))
          and then Ready_Nodes (S) = Ready_Nodes (S)'Old
          and then Free_Nodes (S) = Free_Nodes (S)'Old
          and then (if Current_Task (S) /= Current_Task (S)'Old then
                      State_Of
                        (S, To_Task_Id (Current_Task (S)'Old)) = Ready));

private

   type Ready_Node;
   type Node_Access is access Ready_Node;

   --  Id carries the task identity. Ada reserves the word Task, so the
   --  field is not named Task. Free nodes have Id = No_Task; a ready
   --  node may hold a valid Task_Id.
   type Ready_Node is record
      Id   : Optional_Task_Id := No_Task;
      Next : Node_Access := null;
   end record;

   type Ready_Heads is array (Priority) of Node_Access;

   --  Mathematical observations: no pointer values escape these models.
   --  SPARK.Big_Integers in the installed toolchain renames this standard
   --  Ada package. Big_Natural avoids a machine-sized length bound.
   function List_Length (L : access constant Ready_Node) return Big_Natural
   is (if L = null then 0 else 1 + List_Length (L.Next))
   with Ghost, Subprogram_Variant => (Structural => L);

   function All_Free (L : access constant Ready_Node) return Boolean
   is (L = null or else (L.Id = No_Task and then All_Free (L.Next)))
   with Ghost, Subprogram_Variant => (Structural => L);

   function All_Ready_Ids_Valid
     (L : access constant Ready_Node) return Boolean
   is (L = null or else
         (Has_Task (L.Id) and then All_Ready_Ids_Valid (L.Next)))
   with Ghost, Subprogram_Variant => (Structural => L);

   --  REQ-SCHED-006 at the list-content layer: every reachable node
   --  stores a valid Task_Id whose configured priority is P.
   function All_At_Priority
     (L          : access constant Ready_Node;
      P          : Priority;
      Priorities : Task_Priorities) return Boolean
   is (L = null or else
         (Has_Task (L.Id)
          and then Priorities (To_Task_Id (L.Id)) = P
          and then All_At_Priority (L.Next, P, Priorities)))
   with Ghost, Subprogram_Variant => (Structural => L);

   function Contains_Id
     (L : access constant Ready_Node; Id : Task_Id) return Boolean
   is (L /= null and then
         (L.Id = To_Optional (Id) or else Contains_Id (L.Next, Id)))
   with Ghost, Subprogram_Variant => (Structural => L);

   function Occurrences
     (L : access constant Ready_Node; Id : Task_Id) return Big_Natural
   is (if L = null then 0 else
         Occurrences (L.Next, Id) +
           To_Big_Integer (if L.Id = To_Optional (Id) then 1 else 0))
   with Ghost, Subprogram_Variant => (Structural => L);

   type Occurrence_Map is array (Task_Id) of Big_Natural;
   function Contents (L : access constant Ready_Node) return Occurrence_Map
   with Ghost,
     Post => (for all Id in Task_Id =>
       Contents'Result (Id) = Occurrences (L, Id));

   --  A pledge names the eventual value after an anonymous borrow ends.
   --  This annotation enables borrow reasoning; it does not waive checks.
   function At_End (L : access constant Ready_Node)
     return access constant Ready_Node
   is (L)
   with Ghost, Annotate => (GNATprove, At_End_Borrow);

   type Scheduler is limited record
      Initialized      : Boolean := False;
      Current          : Optional_Task_Id := No_Task;
      Priorities       : Task_Priorities := (others => Priority'First);
      States           : Task_State_Map := (others => Dormant);
      Free_Head        : Node_Access := null;
      Heads            : Ready_Heads := (others => null);
      Free_Node_Count  : Node_Count := 0;
      Ready_Node_Count : Node_Count := 0;
   end record;

   function Is_Initialized (S : Scheduler) return Boolean
   is (S.Initialized);

   function Is_Virgin (S : Scheduler) return Boolean
   is (not S.Initialized
       and then S.Free_Head = null
       and then S.Free_Node_Count = 0
       and then S.Ready_Node_Count = 0
       and then S.Current = No_Task
       and then (for all P in Priority => S.Heads (P) = null));

   function Current_Task (S : Scheduler) return Optional_Task_Id
   is (S.Current);

   function State_Of (S : Scheduler; Id : Task_Id) return Task_State
   is (S.States (Id));

   function Priority_Of (S : Scheduler; Id : Task_Id) return Priority
   is (S.Priorities (Id));

   function Has_Free_Node (S : Scheduler) return Boolean
   is (S.Free_Head /= null);

   function Free_Nodes (S : Scheduler) return Node_Count
   is (S.Free_Node_Count);

   function Ready_Nodes (S : Scheduler) return Node_Count
   is (S.Ready_Node_Count);

   --  REQ-SCHED-001 at the scalar Current/States layer. Distinct from
   --  pointer Representation_Valid: this does not mention queue nodes.
   function Scalar_Scheduler_Valid (S : Scheduler) return Boolean
   is ((if S.Current = No_Task then
          (for all Id in Task_Id => S.States (Id) /= Running)
        else
          S.States (To_Task_Id (S.Current)) = Running
          and then (for all Id in Task_Id =>
                      (if Id /= To_Task_Id (S.Current) then
                         S.States (Id) /= Running))));

   --  Counter-level capacity: a Running task is not on a ready list, so
   --  Ready_Node_Count cannot be Max_Tasks. Combined with
   --  Representation_Valid this yields Has_Free_Node via the existing
   --  free-node lemma. Not a public Yield/Schedule precondition.
   function Running_Has_Free_Slot (S : Scheduler) return Boolean
   is ((if Has_Task (S.Current) then S.Ready_Node_Count < Max_Tasks));

   subtype Length_Map is Ready_Length_Map;

   function Sum (Values : Length_Map) return Big_Natural
   is (Values (0) + Values (1) + Values (2) + Values (3)
       + Values (4) + Values (5) + Values (6) + Values (7))
   with Ghost;

   function Ready_Lengths (S : Scheduler) return Length_Map
   with Ghost,
     Post => (for all P in Priority =>
       Ready_Lengths'Result (P) = List_Length (S.Heads (P)));

   function Occurrences_By_Priority (S : Scheduler; Id : Task_Id)
     return Length_Map
   with Ghost,
     Post => (for all P in Priority =>
       Occurrences_By_Priority'Result (P) = Occurrences (S.Heads (P), Id));

   function Total_Ready_List_Length (S : Scheduler) return Big_Natural
   is (Sum (Ready_Lengths (S)));

   function Ready_List_Length (S : Scheduler; P : Priority) return Big_Natural
   is (List_Length (S.Heads (P)));

   function Copy_States (S : Scheduler) return Task_State_Map
   is (S.States);

   function Copy_Ready_Lengths (S : Scheduler) return Ready_Length_Map
   is (Ready_Lengths (S));

   function No_Ready_Above
     (Lengths : Ready_Length_Map; Bound : Priority) return Boolean
   is (for all P in Priority =>
         (if P > Bound then Lengths (P) = 0));

   function Ready_Occurrences (S : Scheduler; Id : Task_Id)
     return Big_Natural
   is (Sum (Occurrences_By_Priority (S, Id)));

   function Ready_Contains (S : Scheduler; Id : Task_Id) return Boolean
   is (for some P in Priority => Contains_Id (S.Heads (P), Id));

   function All_Ready_Lists_Valid (S : Scheduler) return Boolean
   is (for all P in Priority => All_Ready_Ids_Valid (S.Heads (P)))
   with Ghost;

   --  REQ-SCHED-006 over all eight ready heads.
   function All_Ready_Priorities_Valid (S : Scheduler) return Boolean
   is (for all P in Priority =>
         All_At_Priority (S.Heads (P), P, S.Priorities));

   --  REQ-SCHED-002..005 as one occurrence/state relationship.
   --  SPARK ownership of heap nodes is a different property from this
   --  uniqueness of stored Task_Id values.
   function Ready_Membership_Valid (S : Scheduler) return Boolean
   is (for all T in Task_Id =>
         (if S.States (T) = RTOS.Types.Ready then
            Ready_Occurrences (S, T) = To_Big_Integer (1)
          else
            Ready_Occurrences (S, T) = To_Big_Integer (0)));

   function Free_List_Length (S : Scheduler) return Big_Natural
   is (List_Length (S.Free_Head));

   function Free_List_Valid (S : Scheduler) return Boolean
   is (All_Free (S.Free_Head)
       and then Free_List_Length (S) = To_Big_Integer (S.Free_Node_Count))
   with Ghost;

   function Representation_Valid (S : Scheduler) return Boolean
   is (S.Initialized and then Free_List_Valid (S)
       and then Total_Ready_List_Length (S) =
                  To_Big_Integer (S.Ready_Node_Count)
       and then S.Free_Node_Count + S.Ready_Node_Count = Max_Tasks
       and then All_Ready_Lists_Valid (S));

   --  Central Gold invariant. Composes representation, scalar Current,
   --  ready membership, and queue-priority consistency.
   function Scheduler_Valid (S : Scheduler) return Boolean
   is (Representation_Valid (S)
       and then Scalar_Scheduler_Valid (S)
       and then Ready_Membership_Valid (S)
       and then All_Ready_Priorities_Valid (S));

   --  A null list contributes zero occurrences of every Task_Id.
   procedure Lemma_Null_List_Occurrences (L : access constant Ready_Node)
   with Ghost,
     Pre  => L = null,
     Post => (for all T in Task_Id => Occurrences (L, T) = 0);

   --  Removing a valid ready head decrements only that identity.
   procedure Lemma_Remove_Head_Occurrences
     (Head : access constant Ready_Node;
      Id   : Task_Id)
   with Ghost,
     Pre  => Head /= null
     and then All_Ready_Ids_Valid (Head)
     and then Head.Id = To_Optional (Id),
     Post => Occurrences (Head.Next, Id) = Occurrences (Head, Id) - 1
     and then (for all Other in Task_Id =>
                 (if Other /= Id then
                    Occurrences (Head.Next, Other) =
                      Occurrences (Head, Other)));

   --  All_At_Priority is preserved by removing the head.
   procedure Lemma_All_At_Priority_Tail
     (Head       : access constant Ready_Node;
      P          : Priority;
      Priorities : Task_Priorities)
   with Ghost,
     Pre  => All_At_Priority (Head, P, Priorities),
     Post => (if Head /= null then
                Has_Task (Head.Id)
                and then Priorities (To_Task_Id (Head.Id)) = P
                and then All_At_Priority (Head.Next, P, Priorities));

   --  Priority consistency implies every stored identity is a Task_Id.
   procedure Lemma_Priority_Implies_Valid_Ids
     (L          : access constant Ready_Node;
      P          : Priority;
      Priorities : Task_Priorities)
   with Ghost,
     Subprogram_Variant => (Structural => L),
     Pre  => All_At_Priority (L, P, Priorities),
     Post => All_Ready_Ids_Valid (L);

   --  A positive occurrence under Heads(P) forces the configured
   --  priority of that Task_Id to be P.
   procedure Lemma_Occurrence_Implies_Priority
     (L          : access constant Ready_Node;
      T          : Task_Id;
      P          : Priority;
      Priorities : Task_Priorities)
   with Ghost,
     Subprogram_Variant => (Structural => L),
     Pre  => All_At_Priority (L, P, Priorities)
     and then Occurrences (L, T) > 0,
     Post => Priorities (T) = P;

   --  Empty ready heads contribute no occurrences and satisfy
   --  All_At_Priority for every priority.
   procedure Lemma_Empty_Heads_Membership (S : Scheduler)
   with Ghost,
     Pre  => (for all P in Priority => S.Heads (P) = null),
     Post => (for all T in Task_Id =>
                Ready_Occurrences (S, T) = To_Big_Integer (0))
     and then All_Ready_Priorities_Valid (S)
     and then All_Ready_Lists_Valid (S);

   --  A Ready task's single occurrence sits on its configured queue.
   procedure Lemma_Ready_Task_At_Configured_Priority
     (S : Scheduler;
      T : Task_Id)
   with Ghost,
     Pre  => Scheduler_Valid (S)
     and then S.States (T) = RTOS.Types.Ready,
     Post => Occurrences (S.Heads (S.Priorities (T)), T) =
               To_Big_Integer (1)
     and then S.Heads (S.Priorities (T)) /= null
     and then (for all Q in Priority =>
                 (if Q /= S.Priorities (T) then
                    Occurrences (S.Heads (Q), T) = To_Big_Integer (0)));

   --  Membership plus All_At_Priority imply a nonempty head's stored
   --  identity is Ready and occurs exactly once, only on that queue.
   procedure Lemma_Head_Identity_Ready
     (S : Scheduler;
      P : Priority)
   with Ghost,
     Pre  => Scheduler_Valid (S)
     and then S.Heads (P) /= null,
     Post => Has_Task (S.Heads (P).Id)
     and then S.Priorities (To_Task_Id (S.Heads (P).Id)) = P
     and then S.States (To_Task_Id (S.Heads (P).Id)) = RTOS.Types.Ready
     and then Ready_Occurrences (S, To_Task_Id (S.Heads (P).Id)) =
                To_Big_Integer (1)
     and then Occurrences (S.Heads (P), To_Task_Id (S.Heads (P).Id)) =
                To_Big_Integer (1);

   --  Unfold Ready_Occurrences into the eight per-priority counts.
   procedure Lemma_Unfold_Ready_Occurrences
     (S : Scheduler;
      T : Task_Id)
   with Ghost,
     Post => Ready_Occurrences (S, T) =
               Occurrences (S.Heads (0), T)
               + Occurrences (S.Heads (1), T)
               + Occurrences (S.Heads (2), T)
               + Occurrences (S.Heads (3), T)
               + Occurrences (S.Heads (4), T)
               + Occurrences (S.Heads (5), T)
               + Occurrences (S.Heads (6), T)
               + Occurrences (S.Heads (7), T);

   --  REQ-SCHED-008: the highest nonempty ready head is the greatest
   --  configured priority among all Ready tasks.
   procedure Lemma_Highest_Ready_Is_Greatest_Priority
     (S        : Scheduler;
      Selected : Priority)
   with Ghost,
     Pre  => Scheduler_Valid (S)
     and then S.Heads (Selected) /= null
     and then (for all Q in Priority =>
                 (if Q > Selected then S.Heads (Q) = null)),
     Post => (for all T in Task_Id =>
                (if S.States (T) = RTOS.Types.Ready then
                   S.Priorities (T) <= Selected));

   --  A non-null owned head has mathematical length at least one.
   procedure Lemma_Nonempty_List_Length (Head : access constant Ready_Node)
   with Ghost,
     Pre  => Head /= null,
     Post => List_Length (Head) > 0;

   --  A null head has mathematical length zero.
   procedure Lemma_Empty_List_Length (Head : access constant Ready_Node)
   with Ghost,
     Pre  => Head = null,
     Post => List_Length (Head) = 0;

   --  Bounded scan of the eight ready heads, highest Priority first.
   --  Found is True only when Heads(Selected) is non-null and every
   --  strictly higher priority is empty. No bitmap is introduced.
   procedure Find_Highest_Ready
     (S        : Scheduler;
      Found    : out Boolean;
      Selected : out Priority)
   with
     Pre  => S.Initialized,
     Post => (if Found then
                S.Heads (Selected) /= null
                and then List_Length (S.Heads (Selected)) > 0
                and then (for all Q in Priority =>
                            (if Q > Selected then
                               S.Heads (Q) = null
                               and then List_Length (S.Heads (Q)) = 0))
              else
                (for all Q in Priority =>
                   S.Heads (Q) = null
                   and then List_Length (S.Heads (Q)) = 0));

   --  Translate a completed priority scan into the compact
   --  No_Ready_Above length predicate used by Schedule.
   procedure Lemma_Search_No_Ready_Above
     (S        : Scheduler;
      Found    : Boolean;
      Selected : Priority;
      Bound    : Priority)
   with Ghost,
     Pre  => S.Initialized
     and then (if Found then
                 S.Heads (Selected) /= null
                 and then List_Length (S.Heads (Selected)) > 0
                 and then (for all Q in Priority =>
                             (if Q > Selected then
                                S.Heads (Q) = null
                                and then List_Length (S.Heads (Q)) = 0))
               else
                 (for all Q in Priority =>
                    S.Heads (Q) = null
                    and then List_Length (S.Heads (Q)) = 0)),
     Post => (if not Found or else Selected <= Bound then
                No_Ready_Above (Copy_Ready_Lengths (S), Bound)
              else
                not No_Ready_Above (Copy_Ready_Lengths (S), Bound));

   --  Allocate Max_Tasks nodes onto Head. Head is a local owner so the
   --  scheduler record is not part of the allocation-loop VCs.
   procedure Allocate_Pool
     (Head  : in out Node_Access;
      Count : out Node_Count)
   with
     Pre  => Head = null,
     Post => Head /= null and then Count = Max_Tasks
     and then List_Length (Head) = To_Big_Integer (Max_Tasks)
     and then All_Free (Head);

   --  O(1). Move a detached node onto Head.
   procedure Prepend_Node
     (Head : in out Node_Access;
      Node : in out Node_Access)
   with
     Pre  => Node /= null and then Node.Next = null,
     Post => Node = null and then Head /= null
     and then Head.Id = Node.Id'Old
     and then List_Length (Head) = List_Length (Head)'Old + 1
     and then List_Length (Head.Next) = List_Length (Head)'Old
     and then All_Free (Head.Next) = All_Free (Head)'Old
     and then All_Ready_Ids_Valid (Head.Next) =
                All_Ready_Ids_Valid (Head)'Old
     and then (if Node.Id'Old = No_Task and then All_Free (Head)'Old
               then All_Free (Head))
     and then Contents (Head.Next) = Contents (Head)'Old;

   --  O(1). Move the list head into Node and detach it.
   procedure Remove_Ready_Head
     (Head : in out Node_Access;
      Node : out Node_Access)
   with
     Pre  => Head /= null,
     Post => Node /= null and then Node.Next = null
     and then Node.Id = Head.Id'Old
     and then List_Length (Head) = List_Length (Head)'Old - 1
     and then List_Length (Head) = List_Length (Head.Next)'Old
     and then All_Free (Head) = All_Free (Head.Next)'Old
     and then All_Ready_Ids_Valid (Head) =
                All_Ready_Ids_Valid (Head.Next)'Old
     and then (if All_Ready_Ids_Valid (Head)'Old
               then Has_Task (Node.Id) and then All_Ready_Ids_Valid (Head))
     and then (if All_Free (Head)'Old then All_Free (Head))
     and then Contents (Head) = Contents (Head.Next)'Old
     and then (if Has_Task (Head.Id'Old) then
                 Occurrences (Head, To_Task_Id (Head.Id'Old)) =
                   Contents (Head)'Old (To_Task_Id (Head.Id'Old)) - 1)
     and then (for all Other in Task_Id =>
                 (if Head.Id'Old /= To_Optional (Other) then
                    Occurrences (Head, Other) = Contents (Head)'Old (Other)));

   --  Typed wrapper: remove a ready head while preserving All_At_Priority.
   procedure Remove_Ready_Head_At_Priority
     (Head       : in out Node_Access;
      Node       : out Node_Access;
      P          : Priority;
      Priorities : Task_Priorities)
   with
     Pre  => Head /= null
     and then All_At_Priority (Head, P, Priorities),
     Post => Node /= null and then Node.Next = null
     and then Node.Id = Head.Id'Old
     and then Has_Task (Node.Id)
     and then Priorities (To_Task_Id (Node.Id)) = P
     and then List_Length (Head) = List_Length (Head)'Old - 1
     and then All_Ready_Ids_Valid (Head)
     and then All_At_Priority (Head, P, Priorities)
     and then Contents (Head) = Contents (Head.Next)'Old
     and then Occurrences (Head, To_Task_Id (Node.Id)) =
                Contents (Head)'Old (To_Task_Id (Node.Id)) - 1
     and then (for all Other in Task_Id =>
                 (if Node.Id /= To_Optional (Other) then
                    Occurrences (Head, Other) = Contents (Head)'Old (Other)));

   --  O(1). Move Head's first node into Node, detach it, and mark it
   --  free. Make_Ready passes S.Free_Head as Head.
   procedure Acquire_Node
     (Head : in out Node_Access;
      Node : out Node_Access)
   with
     Pre  => Head /= null,
     Post => Node /= null
     and then Node.Next = null
     and then Node.Id = No_Task
     and then List_Length (Head) = List_Length (Head)'Old - 1
     and then (if All_Free (Head)'Old then All_Free (Head));

   --  O(1). Clear a detached node and move it onto Head. Inverse of
   --  Acquire_Node; Make_Ready does not need it yet.
   procedure Release_Node
     (Head : in out Node_Access;
      Node : in out Node_Access)
   with
     Pre  => Node /= null and then Node.Next = null,
     Post => Node = null and then Head /= null
     and then Head.Id = No_Task
     and then List_Length (Head) = List_Length (Head)'Old + 1
     and then (if All_Free (Head)'Old then All_Free (Head));

   --  O(N). Move a detached node to the tail of Head. Empty lists take
   --  the node as the new head. Nonempty lists are borrowed with an
   --  anonymous access cursor; there is no stored Tail.
   procedure Append_Ready_Tail
     (Head       : in out Node_Access;
      Node       : in out Node_Access;
      P          : Priority;
      Priorities : Task_Priorities)
   with
     Pre  => Node /= null and then Node.Next = null
     and then Has_Task (Node.Id)
     and then Priorities (To_Task_Id (Node.Id)) = P
     and then All_At_Priority (Head, P, Priorities),
     Post => Node = null and then Head /= null
     and then List_Length (Head) = List_Length (Head)'Old + 1
     and then All_Ready_Ids_Valid (Head)
     and then All_At_Priority (Head, P, Priorities)
     and then (for all Id in Task_Id =>
       Occurrences (Head, Id) = Contents (Head)'Old (Id)
         + To_Big_Integer (if Node.Id'Old = To_Optional (Id) then 1 else 0))
     and then Contains_Id (Head, To_Task_Id (Node.Id'Old));

end RTOS.Pointer_Scheduler;
