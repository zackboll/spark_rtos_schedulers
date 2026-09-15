with RTOS.Types;

--  Indexed fixed-priority scheduler.
--
--  Ready membership uses Task_Id links rather than Ada access types:
--
--    Heads (P) -> Task_Id -> Task_Id -> ... -> No_Task
--                                          ^
--                                          |
--                                        Tails (P)
--
--  Heads, Tails, and Next store Optional_Task_Id values. Persistent
--  Head and Tail links are legal because they are identifiers, not
--  writable SPARK aliases.
--
--  Complexity, with Priority_Count statically equal to 8:
--    enqueue tail              O(1)
--    dequeue head              O(1)
--    same-priority yield       O(1)
--    priority selection        at most 8 Nonempty checks
--
--  Selection is therefore O(1) with respect to task count. A later
--  bitmask may reduce the constant factor; this package does not claim
--  a CLZ/BSR-style implementation.
--
--  This is the behavioral + local structural layer. It does not prove
--  complete Next-chain reachability, acyclicity, or membership
--  uniqueness (REQ-SCHED-003..006). Those are the next indexed Gold
--  proof layer.

package RTOS.Indexed_Scheduler
  with SPARK_Mode => On
is

   pragma Unevaluated_Use_Of_Old (Allow);

   use RTOS.Types;

   subtype Ready_Count_Type is Natural range 0 .. Max_Tasks;

   type Scheduler is limited private
     with Default_Initial_Condition =>
       not Is_Initialized (Scheduler);

   function Is_Initialized (S : Scheduler) return Boolean
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

   function Ready_Nodes (S : Scheduler) return Ready_Count_Type
   with
     Pre => Is_Initialized (S);

   function Ready_Head (S : Scheduler; P : Priority) return Optional_Task_Id
   with
     Pre => Is_Initialized (S);

   function Ready_Tail (S : Scheduler; P : Priority) return Optional_Task_Id
   with
     Pre => Is_Initialized (S);

   function Next_Link (S : Scheduler; Id : Task_Id) return Optional_Task_Id
   with
     Pre => Is_Initialized (S);

   function Priority_Nonempty (S : Scheduler; P : Priority) return Boolean
   with
     Pre => Is_Initialized (S);

   function Any_Ready (S : Scheduler) return Boolean
   with
     Pre => Is_Initialized (S);

   type Ready_Priority_Set is array (Priority) of Boolean;
   function Copy_Nonempty (S : Scheduler) return Ready_Priority_Set
     with Ghost;

   function Copy_States (S : Scheduler) return Task_State_Map
     with Ghost;

   function No_Ready_Above (S : Scheduler; Bound : Priority) return Boolean
     with Ghost;

   function Running_Has_Ready_Slot (S : Scheduler) return Boolean
     with Ghost;

   function Scalar_Scheduler_Valid (S : Scheduler) return Boolean
     with Ghost;

   function Queue_Structure_Valid (S : Scheduler) return Boolean
     with Ghost;

   function Endpoint_Ready_Valid (S : Scheduler) return Boolean
     with Ghost;

   function Nonready_Unlinked (S : Scheduler) return Boolean
     with Ghost;

   function Next_Edges_Valid (S : Scheduler) return Boolean
     with Ghost;

   function No_Self_Loops (S : Scheduler) return Boolean
     with Ghost;

   function Heads_Unreferenced (S : Scheduler) return Boolean
     with Ghost;

   function Next_Injective (S : Scheduler) return Boolean
     with Ghost;

   function Ready_Prefix
     (States : Task_State_Map; Last : Natural) return Natural
   with Ghost,
     Pre => Last <= Max_Tasks,
     Post => Ready_Prefix'Result <= Last,
     Subprogram_Variant => (Decreases => Last);

   function Count_Ready_States
     (States : Task_State_Map) return Ready_Count_Type
     with Ghost,
       Post => Count_Ready_States'Result = Ready_Prefix (States, Max_Tasks);

   function Ready_Count_State_Valid (S : Scheduler) return Boolean
     with Ghost;

   function Indexed_Representation_Valid (S : Scheduler) return Boolean
     with Ghost;

   function Indexed_Scheduler_Valid (S : Scheduler) return Boolean
     with Ghost;

   procedure Initialize
     (S          : out Scheduler;
      Priorities : Task_Priorities)
   with
     Post => Is_Initialized (S)
     and then Current_Task (S) = No_Task
     and then Ready_Nodes (S) = 0
     and then (for all Id in Task_Id => State_Of (S, Id) = Dormant)
     and then (for all P in Priority =>
                 Ready_Head (S, P) = No_Task
                 and then Ready_Tail (S, P) = No_Task
                 and then not Priority_Nonempty (S, P))
     and then (for all Id in Task_Id => Next_Link (S, Id) = No_Task)
     and then Indexed_Scheduler_Valid (S);

   --  O(1) tail enqueue of Id at its configured priority.
   procedure Make_Ready (S : in out Scheduler; Id : Task_Id)
   with
     Pre  => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then State_Of (S, Id) /= Ready
     and then State_Of (S, Id) /= Running
     and then Ready_Nodes (S) < Max_Tasks
     and then Next_Link (S, Id) = No_Task,
     Post => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then State_Of (S, Id) = Ready
     and then Ready_Nodes (S) = Ready_Nodes (S)'Old + 1
     and then Ready_Tail (S, Priority_Of (S, Id)) = To_Optional (Id)
     and then Next_Link (S, Id) = No_Task
     and then Current_Task (S) = Current_Task (S)'Old
     and then Priority_Nonempty (S, Priority_Of (S, Id))
     and then (for all Other in Task_Id =>
                 (if Other /= Id then
                    State_Of (S, Other) = Copy_States (S)'Old (Other)));

   --  Block the currently running task. Ready links are not changed.
   procedure Block (S : in out Scheduler; Id : Task_Id)
   with
     Pre  => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then Current_Task (S) = To_Optional (Id)
     and then State_Of (S, Id) = Running,
     Post => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then Current_Task (S) = No_Task
     and then State_Of (S, Id) = Blocked
     and then Ready_Nodes (S) = Ready_Nodes (S)'Old
     and then (for all Other in Task_Id =>
                 (if Other /= Id then
                    State_Of (S, Other) = Copy_States (S)'Old (Other)))
     and then (for all Other in Task_Id => State_Of (S, Other) /= Running);

   --  Requeue Current at its priority tail in O(1), then Select_Next.
   --  Ordered FIFO is an implementation property, not yet a proved
   --  sequence model.
   procedure Yield (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then Running_Has_Ready_Slot (S)
     and then Has_Task (Current_Task (S))
     and then State_Of (S, To_Task_Id (Current_Task (S))) = Running,
     Post => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then Has_Task (Current_Task (S))
     and then State_Of (S, To_Task_Id (Current_Task (S))) = Running
     and then Ready_Nodes (S) = Ready_Nodes (S)'Old
     and then Next_Link (S, To_Task_Id (Current_Task (S))) = No_Task
     and then (if Current_Task (S) /= Current_Task (S)'Old then
                 State_Of (S, To_Task_Id (Current_Task (S)'Old)) = Ready);

   --  Dispatch the highest nonempty ready head, or remain idle.
   procedure Select_Next (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then Current_Task (S) = No_Task,
     Post => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then (if not Any_Ready (S)'Old then
        Current_Task (S) = No_Task
        and then Ready_Nodes (S) = Ready_Nodes (S)'Old
        and then (for all Id in Task_Id =>
                    State_Of (S, Id) = Copy_States (S)'Old (Id))
      else
        Has_Task (Current_Task (S))
        and then State_Of (S, To_Task_Id (Current_Task (S))) = Running
        and then Ready_Nodes (S) = Ready_Nodes (S)'Old - 1
        and then Next_Link (S, To_Task_Id (Current_Task (S))) = No_Task
        and then (for some P in Priority =>
                    Copy_Nonempty (S)'Old (P)
                    and then Priority_Of (S, To_Task_Id (Current_Task (S))) = P
                    and then (for all Q in Priority =>
                                (if Q > P then
                                   not Copy_Nonempty (S)'Old (Q))))
        and then (for all Other in Task_Id =>
                    (if Other /= To_Task_Id (Current_Task (S)) then
                       State_Of (S, Other) = Copy_States (S)'Old (Other))));

   --  Idle: Select_Next. Running: preempt only for a strictly higher
   --  nonempty ready priority. Equal priority does not preempt.
   procedure Schedule (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then Running_Has_Ready_Slot (S),
     Post => Is_Initialized (S)
     and then Indexed_Scheduler_Valid (S)
     and then (if Has_Task (Current_Task (S)) then
                 State_Of (S, To_Task_Id (Current_Task (S))) = Running
                 and then Next_Link
                            (S, To_Task_Id (Current_Task (S))) = No_Task),
     Contract_Cases =>
       (Current_Task (S) = No_Task and then not Any_Ready (S) =>
          Current_Task (S) = No_Task
          and then Ready_Nodes (S) = Ready_Nodes (S)'Old
          and then (for all Id in Task_Id =>
                      State_Of (S, Id) = Copy_States (S)'Old (Id)),
        Current_Task (S) = No_Task and then Any_Ready (S) =>
          Has_Task (Current_Task (S))
          and then Ready_Nodes (S) = Ready_Nodes (S)'Old - 1,
        Has_Task (Current_Task (S))
          and then No_Ready_Above
                     (S, Priority_Of (S, To_Task_Id (Current_Task (S)))) =>
          Current_Task (S) = Current_Task (S)'Old
          and then Ready_Nodes (S) = Ready_Nodes (S)'Old
          and then (for all Id in Task_Id =>
                      State_Of (S, Id) = Copy_States (S)'Old (Id)),
        others =>
          Has_Task (Current_Task (S))
          and then Ready_Nodes (S) = Ready_Nodes (S)'Old
          and then (if Current_Task (S) /= Current_Task (S)'Old then
                      State_Of
                        (S, To_Task_Id (Current_Task (S)'Old)) = Ready));

private

   type Task_Links is array (Task_Id) of Optional_Task_Id;
   type Priority_Links is array (Priority) of Optional_Task_Id;

   type Scheduler is limited record
      Initialized : Boolean := False;
      Current     : Optional_Task_Id := No_Task;
      Priorities  : Task_Priorities := (others => Priority'First);
      States      : Task_State_Map := (others => Dormant);
      Heads       : Priority_Links := (others => No_Task);
      Tails       : Priority_Links := (others => No_Task);
      Next        : Task_Links := (others => No_Task);
      Nonempty    : Ready_Priority_Set := (others => False);
      Ready_Count : Ready_Count_Type := 0;
   end record;

   function Is_Initialized (S : Scheduler) return Boolean
   is (S.Initialized);

   function Current_Task (S : Scheduler) return Optional_Task_Id
   is (S.Current);

   function State_Of (S : Scheduler; Id : Task_Id) return Task_State
   is (S.States (Id));

   function Priority_Of (S : Scheduler; Id : Task_Id) return Priority
   is (S.Priorities (Id));

   function Ready_Nodes (S : Scheduler) return Ready_Count_Type
   is (S.Ready_Count);

   function Ready_Head (S : Scheduler; P : Priority) return Optional_Task_Id
   is (S.Heads (P));

   function Ready_Tail (S : Scheduler; P : Priority) return Optional_Task_Id
   is (S.Tails (P));

   function Next_Link (S : Scheduler; Id : Task_Id) return Optional_Task_Id
   is (S.Next (Id));

   function Priority_Nonempty (S : Scheduler; P : Priority) return Boolean
   is (S.Nonempty (P));

   function Any_Ready (S : Scheduler) return Boolean
   is (for some P in Priority => S.Nonempty (P));

   function Copy_Nonempty (S : Scheduler) return Ready_Priority_Set
   is (S.Nonempty);

   --  Local edge observations, not a transitive chain model.
   function Next_Edges_Valid (S : Scheduler) return Boolean
   is (for all T in Task_Id =>
         (if Has_Task (S.Next (T)) then
            S.States (To_Task_Id (S.Next (T))) = Ready
            and then S.Priorities (To_Task_Id (S.Next (T))) =
                       S.Priorities (T)));

   function No_Self_Loops (S : Scheduler) return Boolean
   is (for all T in Task_Id => S.Next (T) /= To_Optional (T));

   function Heads_Unreferenced (S : Scheduler) return Boolean
   is (for all P in Priority =>
         (if Has_Task (S.Heads (P)) then
            (for all T in Task_Id => S.Next (T) /= S.Heads (P))));

   function Next_Injective (S : Scheduler) return Boolean
   is (for all T in Task_Id =>
         (for all U in Task_Id =>
            (if Has_Task (S.Next (T)) and then S.Next (T) = S.Next (U)
             then T = U)));

   function Ready_Prefix
     (States : Task_State_Map; Last : Natural) return Natural
   is (if Last = 0 then 0 else
         Ready_Prefix (States, Last - 1)
         + (if States (Task_Id (Last)) = Ready then 1 else 0));

   procedure Lemma_State_Update
     (Before, After : Task_State_Map; Id : Task_Id; Last : Natural)
   with Ghost,
     Pre => Last <= Max_Tasks
       and then (for all T in Task_Id =>
                   (if T /= Id then Before (T) = After (T))),
     Post => Integer (Ready_Prefix (After, Last)) =
       Integer (Ready_Prefix (Before, Last))
       + (if Natural (Id) <= Last then
            (if After (Id) = Ready then 1 else 0)
            - (if Before (Id) = Ready then 1 else 0)
          else 0),
     Subprogram_Variant => (Decreases => Last);

   --  Scalar accounting only: disconnected Ready components are admitted.
   function Ready_Count_State_Valid (S : Scheduler) return Boolean
   is (S.Ready_Count = Count_Ready_States (S.States));

   function Copy_States (S : Scheduler) return Task_State_Map
   is (S.States);

   function No_Ready_Above (S : Scheduler; Bound : Priority) return Boolean
   is (for all P in Priority =>
         (if P > Bound then not S.Nonempty (P)));

   function Running_Has_Ready_Slot (S : Scheduler) return Boolean
   is (if Has_Task (S.Current) then S.Ready_Count < Max_Tasks);

   --  REQ-SCHED-001 at the scalar Current/States layer.
   function Scalar_Scheduler_Valid (S : Scheduler) return Boolean
   is ((if S.Current = No_Task then
          (for all Id in Task_Id => S.States (Id) /= Running)
        else
          S.States (To_Task_Id (S.Current)) = Running
          and then (for all Id in Task_Id =>
                      (if Id /= To_Task_Id (S.Current) then
                         S.States (Id) /= Running))));

   --  Head/Tail empty equivalence, Nonempty flags, and tail terminator.
   --  This does not model full chain reachability.
   function Queue_Structure_Valid (S : Scheduler) return Boolean
   is (for all P in Priority =>
         ((S.Heads (P) = No_Task) = (S.Tails (P) = No_Task)
          and then S.Nonempty (P) = (S.Heads (P) /= No_Task)
          and then (if Has_Task (S.Tails (P)) then
                      S.Next (To_Task_Id (S.Tails (P))) = No_Task)));

   --  Endpoint facts that do not require walking the whole chain.
   function Endpoint_Ready_Valid (S : Scheduler) return Boolean
   is (for all P in Priority =>
         ((if Has_Task (S.Heads (P)) then
             S.States (To_Task_Id (S.Heads (P))) = Ready
             and then S.Priorities (To_Task_Id (S.Heads (P))) = P)
          and then
          (if Has_Task (S.Tails (P)) then
             S.States (To_Task_Id (S.Tails (P))) = Ready
             and then S.Priorities (To_Task_Id (S.Tails (P))) = P)));

   function Nonready_Unlinked (S : Scheduler) return Boolean
   is (for all T in Task_Id =>
         (if S.States (T) /= Ready then S.Next (T) = No_Task));

   function Indexed_Representation_Valid (S : Scheduler) return Boolean
   is (Queue_Structure_Valid (S)
       and then Endpoint_Ready_Valid (S)
       and then Nonready_Unlinked (S)
        --  One-edge semantics, head exclusion, and unique predecessors.
        --  None of these asserts reachability or global acyclicity.
        and then Next_Edges_Valid (S)
        and then Heads_Unreferenced (S)
        and then Next_Injective (S));

   function Indexed_Scheduler_Valid (S : Scheduler) return Boolean
   is (S.Initialized
       and then Indexed_Representation_Valid (S)
       and then Scalar_Scheduler_Valid (S)
        and then Ready_Count_State_Valid (S));

   --  O(1). Append Id at the tail of priority P. Does not update
   --  Ready_Count; the public caller owns counting. Id must already be
   --  Ready so endpoint Ready/Priority facts are preserved.
   procedure Enqueue
     (S  : in out Scheduler;
      P  : Priority;
      Id : Task_Id)
   with
     Pre  => S.Initialized
     and then Queue_Structure_Valid (S)
     and then Endpoint_Ready_Valid (S)
      and then Next_Edges_Valid (S)
      and then Heads_Unreferenced (S)
      and then Next_Injective (S)
     and then Nonready_Unlinked (S)
     and then S.Priorities (Id) = P
     and then S.States (Id) = Ready
     and then S.Next (Id) = No_Task
      and then (for all T in Task_Id =>
                  S.Next (T) /= To_Optional (Id))
     and then (for all Q in Priority =>
                 S.Heads (Q) /= To_Optional (Id)
                 and then S.Tails (Q) /= To_Optional (Id)),
     Post => S.Initialized
     and then Queue_Structure_Valid (S)
     and then Endpoint_Ready_Valid (S)
      and then Next_Edges_Valid (S)
      and then Heads_Unreferenced (S)
      and then Next_Injective (S)
     and then Nonready_Unlinked (S)
     and then S.Tails (P) = To_Optional (Id)
     and then S.Heads (P) /= No_Task
     and then S.Nonempty (P)
     and then S.Next (Id) = No_Task
     and then (if S.Heads (P)'Old = No_Task then
                 S.Heads (P) = To_Optional (Id)
               else
                 S.Heads (P) = S.Heads (P)'Old
                 and then Has_Task (S.Tails (P)'Old)
                 and then S.Next (To_Task_Id (S.Tails (P)'Old)) =
                            To_Optional (Id))
     and then (for all Q in Priority =>
                 (if Q /= P then
                    S.Heads (Q) = S.Heads'Old (Q)
                    and then S.Tails (Q) = S.Tails'Old (Q)
                    and then S.Nonempty (Q) = S.Nonempty'Old (Q)))
     and then S.States = S.States'Old
      and then Count_Ready_States (S.States) =
                 Count_Ready_States (S.States)'Old
     and then S.Current = S.Current'Old
     and then S.Priorities = S.Priorities'Old
     and then S.Ready_Count = S.Ready_Count'Old;

   --  O(1). Remove and return the head of priority P.
   procedure Dequeue
     (S  : in out Scheduler;
      P  : Priority;
      Id : out Task_Id)
   with
     Pre  => S.Initialized
     and then Queue_Structure_Valid (S)
     and then Endpoint_Ready_Valid (S)
      and then Next_Edges_Valid (S)
      and then Heads_Unreferenced (S)
      and then Next_Injective (S)
     and then S.Nonempty (P)
     and then S.Heads (P) /= No_Task,
     Post => S.Initialized
     and then Queue_Structure_Valid (S)
     and then Id = To_Task_Id (S.Heads (P)'Old)
     and then S.Priorities (Id) = P
     and then S.States (Id) = Ready
     and then S.Next (Id) = No_Task
     and then S.Heads (P) = S.Next'Old (To_Task_Id (S.Heads (P)'Old))
     and then (if S.Heads (P) = No_Task then
                 S.Tails (P) = No_Task
                 and then not S.Nonempty (P)
               else
                 S.Tails (P) = S.Tails (P)'Old
                 and then S.Nonempty (P))
     and then (for all Q in Priority =>
                 (if Q /= P then
                    S.Heads (Q) = S.Heads'Old (Q)
                    and then S.Tails (Q) = S.Tails'Old (Q)
                    and then S.Nonempty (Q) = S.Nonempty'Old (Q)))
     and then S.States = S.States'Old
      and then Count_Ready_States (S.States) =
                 Count_Ready_States (S.States)'Old
     and then S.Current = S.Current'Old
     and then S.Priorities = S.Priorities'Old
     and then S.Ready_Count = S.Ready_Count'Old
     and then (for all T in Task_Id =>
                 (if T /= Id then S.Next (T) = S.Next'Old (T)));

   --  At most eight Boolean checks, highest Priority first.
   procedure Find_Highest_Ready
     (S        : Scheduler;
      Found    : out Boolean;
      Selected : out Priority)
   with
     Pre  => S.Initialized
     and then Queue_Structure_Valid (S),
     Post => (if Found then
                S.Nonempty (Selected)
                and then S.Heads (Selected) /= No_Task
                and then (for all Q in Priority =>
                            (if Q > Selected then not S.Nonempty (Q)))
              else
                (for all Q in Priority => not S.Nonempty (Q)));

   --  Translate a completed priority scan into No_Ready_Above.
   procedure Lemma_Search_No_Ready_Above
     (S        : Scheduler;
      Found    : Boolean;
      Selected : Priority;
      Bound    : Priority)
   with Ghost,
     Pre  => S.Initialized
     and then (if Found then
                 S.Nonempty (Selected)
                 and then (for all Q in Priority =>
                             (if Q > Selected then not S.Nonempty (Q)))
               else
                 (for all Q in Priority => not S.Nonempty (Q))),
     Post => (if not Found or else Selected <= Bound then
                No_Ready_Above (S, Bound)
              else
                not No_Ready_Above (S, Bound));

end RTOS.Indexed_Scheduler;
