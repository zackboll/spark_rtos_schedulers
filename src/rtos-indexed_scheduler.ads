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

   subtype Global_Occurrence_Count is
     Natural range 0 .. Priority_Count * Max_Tasks;

   type Ready_Length_Map is array (Priority) of Ready_Count_Type;
   type Ready_Occurrence_Map is array (Task_Id) of Global_Occurrence_Count;

   function All_Ready_Chains_Terminate (S : Scheduler) return Boolean
     with Ghost;
   function Ready_Occurrences (S : Scheduler; Id : Task_Id)
     return Global_Occurrence_Count with Ghost;
   function Ready_Contains (S : Scheduler; Id : Task_Id) return Boolean
     with Ghost;
   function Total_Ready_Chain_Length (S : Scheduler)
     return Global_Occurrence_Count with Ghost;
   function Tails_Reachable (S : Scheduler) return Boolean with Ghost;
   function All_Reachable_Tasks_Ready (S : Scheduler) return Boolean
     with Ghost;
   function All_Reachable_Priorities_Valid (S : Scheduler) return Boolean
     with Ghost;

   function Ready_Membership_Valid (S : Scheduler) return Boolean
     with Ghost;
   function Ready_Chain_Count_Valid (S : Scheduler) return Boolean
     with Ghost;
   --  Not yet part of the stable behavioral invariant.
   function Indexed_Reachability_Model_Valid (S : Scheduler) return Boolean
     with Ghost;

   function Copy_Ready_Occurrences (S : Scheduler) return Ready_Occurrence_Map
     with Ghost;
   function Copy_Ready_Lengths (S : Scheduler) return Ready_Length_Map
     with Ghost;

   procedure Lemma_Local_Reachability (S : Scheduler)
   with Ghost,
     Pre => Endpoint_Ready_Valid (S) and then Next_Edges_Valid (S),
     Post => All_Reachable_Tasks_Ready (S)
       and then All_Reachable_Priorities_Valid (S);

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
      and then Indexed_Reachability_Model_Valid (S)
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

   --  Fuel, not graph acyclicity, guarantees termination of this model.
   function Follow
     (Links : Task_Links; Start : Optional_Task_Id; Steps : Natural)
      return Optional_Task_Id
   with Ghost,
     Pre => Steps <= Max_Tasks,
     Post => (if Start = No_Task then Follow'Result = No_Task),
     Subprogram_Variant => (Decreases => Steps);

   function Follow
     (Links : Task_Links; Start : Optional_Task_Id; Steps : Natural)
      return Optional_Task_Id
   is (if Steps = 0 or else Start = No_Task then Start
       else Follow (Links, Links (To_Task_Id (Start)), Steps - 1));

   --  Sum positions 0 .. Fuel - 1, even for malformed cyclic links.
   function Length_Prefix
     (Links : Task_Links; Head : Optional_Task_Id; Fuel : Natural)
      return Ready_Count_Type
   with Ghost,
     Pre => Fuel <= Max_Tasks,
     Post => Length_Prefix'Result <= Fuel
       and then (if Head = No_Task then Length_Prefix'Result = 0)
       and then (if Head /= No_Task and then Fuel > 0 then
                   Length_Prefix'Result > 0),
     Subprogram_Variant => (Decreases => Fuel);

   function Length_Prefix
     (Links : Task_Links; Head : Optional_Task_Id; Fuel : Natural)
      return Ready_Count_Type
   is (if Fuel = 0 then 0 else
         Length_Prefix (Links, Head, Fuel - 1)
         + (if Follow (Links, Head, Fuel - 1) /= No_Task then 1 else 0));

   function Occurrence_Prefix
     (Links : Task_Links; Head : Optional_Task_Id; Id : Task_Id;
      Fuel : Natural) return Ready_Count_Type
   with Ghost,
     Pre => Fuel <= Max_Tasks,
     Post => Occurrence_Prefix'Result <= Fuel
       and then (if Head = No_Task then Occurrence_Prefix'Result = 0),
     Subprogram_Variant => (Decreases => Fuel);

   function Occurrence_Prefix
     (Links : Task_Links; Head : Optional_Task_Id; Id : Task_Id;
      Fuel : Natural) return Ready_Count_Type
   is (if Fuel = 0 then 0 else
         Occurrence_Prefix (Links, Head, Id, Fuel - 1)
         + (if Follow (Links, Head, Fuel - 1) = To_Optional (Id)
            then 1 else 0));

   function Chain_Length
     (Links : Task_Links; Head : Optional_Task_Id) return Ready_Count_Type
   is (Length_Prefix (Links, Head, Max_Tasks)) with Ghost;

   function Chain_Occurrences
     (Links : Task_Links; Head : Optional_Task_Id; Id : Task_Id)
      return Ready_Count_Type
   is (Occurrence_Prefix (Links, Head, Id, Max_Tasks)) with Ghost;

   function Chain_Terminates
     (Links : Task_Links; Head : Optional_Task_Id) return Boolean
   is (Follow (Links, Head, Max_Tasks) = No_Task) with Ghost;

   procedure Lemma_Follow_Null
     (Links : Task_Links; Steps : Natural)
   with Ghost,
     Pre => Steps <= Max_Tasks,
     Post => Follow (Links, No_Task, Steps) = No_Task,
     Subprogram_Variant => (Decreases => Steps);

   --  Follow (Start, A + B) resumes from the node at position A.
   procedure Lemma_Follow_Compose
     (Links : Task_Links;
      Start : Optional_Task_Id;
      A, B  : Natural)
   with Ghost,
     Pre => A <= Max_Tasks
       and then B <= Max_Tasks
       and then A + B <= Max_Tasks,
     Post => Follow (Links, Start, A + B) =
               Follow (Links, Follow (Links, Start, A), B),
     Subprogram_Variant => (Decreases => A);

   --  Once Follow hits No_Task, later fuel stays No_Task.
   procedure Lemma_Follow_After_Null
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      K     : Natural;
      Steps : Natural)
   with Ghost,
     Pre => K <= Max_Tasks
       and then Steps <= Max_Tasks
       and then K <= Steps
       and then Follow (Links, Head, K) = No_Task,
     Post => Follow (Links, Head, Steps) = No_Task;

   --  Changing Next (Changed) does not affect Follow while Changed
   --  is never used as a step source.
   function Path_Avoids
     (Links   : Task_Links;
      Start   : Optional_Task_Id;
      Changed : Task_Id;
      Fuel    : Natural) return Boolean
   with Ghost,
     Pre => Fuel <= Max_Tasks,
     Subprogram_Variant => (Decreases => Fuel);

   function Path_Avoids
     (Links   : Task_Links;
      Start   : Optional_Task_Id;
      Changed : Task_Id;
      Fuel    : Natural) return Boolean
   is (if Fuel = 0 or else Start = No_Task then True
       else Start /= To_Optional (Changed)
            and then Path_Avoids
                       (Links,
                        Links (To_Task_Id (Start)),
                        Changed,
                        Fuel - 1));

   procedure Lemma_Follow_Frame
     (Before, After : Task_Links;
      Start         : Optional_Task_Id;
      Changed       : Task_Id;
      Steps         : Natural)
   with Ghost,
     Pre => Steps <= Max_Tasks
       and then (for all T in Task_Id =>
                   (if T /= Changed then Before (T) = After (T)))
       and then Path_Avoids (Before, Start, Changed, Steps),
     Post => Follow (Before, Start, Steps) = Follow (After, Start, Steps),
     Subprogram_Variant => (Decreases => Steps);

   --  Prefix length equals the count of non-null Follow positions.
   procedure Lemma_Length_Prefix_Unfold
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Fuel  : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks,
     Post => Length_Prefix (Links, Head, Fuel) =
               (if Fuel = 0 then 0
                else Length_Prefix (Links, Head, Fuel - 1)
                     + (if Follow (Links, Head, Fuel - 1) /= No_Task
                        then 1 else 0)),
     Subprogram_Variant => (Decreases => Fuel);

   procedure Lemma_Occurrence_Prefix_Unfold
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Id    : Task_Id;
      Fuel  : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks,
     Post => Occurrence_Prefix (Links, Head, Id, Fuel) =
               (if Fuel = 0 then 0
                else Occurrence_Prefix (Links, Head, Id, Fuel - 1)
                     + (if Follow (Links, Head, Fuel - 1) = To_Optional (Id)
                        then 1 else 0)),
     Subprogram_Variant => (Decreases => Fuel);

   --  Empty heads contribute no length or occurrences.
   procedure Lemma_Empty_Chain
     (Links : Task_Links; Id : Task_Id)
   with Ghost,
     Post => Chain_Length (Links, No_Task) = 0
       and then Chain_Occurrences (Links, No_Task, Id) = 0
       and then Chain_Terminates (Links, No_Task);

   --  A singleton terminator has length 1 and one occurrence of Id.
   procedure Lemma_Singleton_Chain
     (Links : Task_Links; Id : Task_Id)
   with Ghost,
     Pre => Links (Id) = No_Task,
     Post => Chain_Length (Links, To_Optional (Id)) = 1
       and then Chain_Occurrences (Links, To_Optional (Id), Id) = 1
       and then Chain_Terminates (Links, To_Optional (Id));

   --  If Follow never uses Changed as a source, length and occurrences
   --  of that chain are unchanged by rewriting Next (Changed).
   procedure Lemma_Length_Frame
     (Before, After : Task_Links;
      Head          : Optional_Task_Id;
      Changed       : Task_Id;
      Fuel          : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks
       and then (for all T in Task_Id =>
                   (if T /= Changed then Before (T) = After (T)))
       and then Path_Avoids (Before, Head, Changed, Fuel),
     Post => Length_Prefix (Before, Head, Fuel) =
               Length_Prefix (After, Head, Fuel)
       and then Follow (Before, Head, Fuel) = Follow (After, Head, Fuel),
     Subprogram_Variant => (Decreases => Fuel);

   procedure Lemma_Occurrence_Frame
     (Before, After : Task_Links;
      Head          : Optional_Task_Id;
      Changed       : Task_Id;
      Id            : Task_Id;
      Fuel          : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks
       and then (for all T in Task_Id =>
                   (if T /= Changed then Before (T) = After (T)))
       and then Path_Avoids (Before, Head, Changed, Fuel),
     Post => Occurrence_Prefix (Before, Head, Id, Fuel) =
               Occurrence_Prefix (After, Head, Id, Fuel),
     Subprogram_Variant => (Decreases => Fuel);

   --  Removing the first node shifts Follow by one.
   procedure Lemma_Follow_Shift
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Steps : Natural)
   with Ghost,
     Pre => Steps < Max_Tasks and then Head /= No_Task,
     Post => Follow (Links, Head, Steps + 1) =
               Follow (Links, Links (To_Task_Id (Head)), Steps);

   --  Prefix after the head is the remaining prefix.
   procedure Lemma_Length_Tail_Prefix
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Fuel  : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks and then Head /= No_Task,
     Post => Length_Prefix (Links, Head, Fuel) =
               (if Fuel = 0 then 0
                else 1 + Length_Prefix
                           (Links, Links (To_Task_Id (Head)), Fuel - 1)),
     Subprogram_Variant => (Decreases => Fuel);

   procedure Lemma_Occurrence_Tail_Prefix
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Id    : Task_Id;
      Fuel  : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks and then Head /= No_Task,
     Post => Occurrence_Prefix (Links, Head, Id, Fuel) =
               (if Fuel = 0 then 0
                else (if Head = To_Optional (Id) then 1 else 0)
                     + Occurrence_Prefix
                         (Links, Links (To_Task_Id (Head)), Id, Fuel - 1)),
     Subprogram_Variant => (Decreases => Fuel);

   --  Dequeue of a terminating head decreases length by one.
   procedure Lemma_Dequeue_Length
     (Links : Task_Links;
      Head  : Optional_Task_Id)
   with Ghost,
     Pre => Head /= No_Task
       and then Chain_Terminates (Links, Head),
     Post => Chain_Length (Links, Links (To_Task_Id (Head))) =
               Chain_Length (Links, Head) - 1
       and then Chain_Terminates (Links, Links (To_Task_Id (Head)));

   --  Dequeue of a terminating head decreases only that identity.
   procedure Lemma_Dequeue_Occurrences
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Id    : Task_Id)
   with Ghost,
     Pre => Head /= No_Task
       and then Chain_Terminates (Links, Head),
     Post =>
       (if Head = To_Optional (Id) then
          Chain_Occurrences (Links, Links (To_Task_Id (Head)), Id) =
            Chain_Occurrences (Links, Head, Id) - 1
        else
          Chain_Occurrences (Links, Links (To_Task_Id (Head)), Id) =
            Chain_Occurrences (Links, Head, Id));

   --  Path_Avoids is preserved by extra unused fuel.
   procedure Lemma_Path_Avoids_Shorter
     (Links   : Task_Links;
      Start   : Optional_Task_Id;
      Changed : Task_Id;
      Fuel    : Natural;
      Less    : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks
       and then Less <= Fuel
       and then Path_Avoids (Links, Start, Changed, Fuel),
     Post => Path_Avoids (Links, Start, Changed, Less),
     Subprogram_Variant => (Decreases => Fuel);

   --  A terminating chain never uses a node after its null terminator.
   --  Therefore rewriting Next of a node that occurs zero times cannot
   --  change Follow on that chain.
   procedure Lemma_Zero_Occurrence_Avoids
     (Links   : Task_Links;
      Head    : Optional_Task_Id;
      Changed : Task_Id;
      Fuel    : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks
       and then Chain_Terminates (Links, Head)
       and then Chain_Occurrences (Links, Head, Changed) = 0,
     Post => Path_Avoids (Links, Head, Changed, Fuel),
     Subprogram_Variant => (Decreases => Fuel);

   --  Once Follow hits No_Task at K, later prefixes are unchanged.
   procedure Lemma_Unreachable_Link_Frame
     (Before, After : Task_Links;
      Head          : Optional_Task_Id;
      Changed       : Task_Id)
   with Ghost,
     Pre => Chain_Terminates (Before, Head)
       and then Chain_Occurrences (Before, Head, Changed) = 0
       and then (for all T in Task_Id =>
                   (if T /= Changed then Before (T) = After (T))),
     Post => Chain_Terminates (After, Head)
       and then Chain_Length (After, Head) = Chain_Length (Before, Head)
       and then (for all K in 0 .. Max_Tasks =>
                   Follow (After, Head, K) = Follow (Before, Head, K))
       and then (for all T in Task_Id =>
                   Chain_Occurrences (After, Head, T) =
                     Chain_Occurrences (Before, Head, T));

   --  Once Follow hits No_Task at K, later prefixes are unchanged.
   procedure Lemma_Terminated_Prefix
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Id    : Task_Id;
      K     : Natural;
      Fuel  : Natural)
   with Ghost,
     Pre => K <= Max_Tasks
       and then Fuel <= Max_Tasks
       and then K <= Fuel
       and then Follow (Links, Head, K) = No_Task,
     Post => Length_Prefix (Links, Head, Fuel) = Length_Prefix (Links, Head, K)
       and then Occurrence_Prefix (Links, Head, Id, Fuel) =
                  Occurrence_Prefix (Links, Head, Id, K),
     Subprogram_Variant => (Decreases => Fuel);

   --  A non-null position Fuel - 1 forces every earlier position present.
   procedure Lemma_Present_Implies_Full
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Fuel  : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks
       and then (if Fuel > 0 then
                   Follow (Links, Head, Fuel - 1) /= No_Task),
     Post => Length_Prefix (Links, Head, Fuel) = Fuel,
     Subprogram_Variant => (Decreases => Fuel);

   procedure Lemma_Short_Chain_Null
     (Links : Task_Links;
      Head  : Optional_Task_Id)
   with Ghost,
     Pre => Chain_Length (Links, Head) < Max_Tasks,
     Post => Follow (Links, Head, Max_Tasks - 1) = No_Task;

   --  Tail -> Id -> No_Task is a terminating two-node chain.
   procedure Lemma_Two_Node_Chain
     (Links  : Task_Links;
      First  : Task_Id;
      Second : Task_Id)
   with Ghost,
     Pre => First /= Second
       and then Links (First) = To_Optional (Second)
       and then Links (Second) = No_Task,
     Post => Chain_Terminates (Links, To_Optional (First))
       and then Chain_Length (Links, To_Optional (First)) = 2
       and then Chain_Occurrences (Links, To_Optional (First), First) = 1
       and then Chain_Occurrences (Links, To_Optional (First), Second) = 1
       and then (for all Other in Task_Id =>
                   (if Other /= First and then Other /= Second then
                      Chain_Occurrences
                        (Links, To_Optional (First), Other) = 0));

   --  Appending a fresh terminator at a reachable Tail increases length
   --  by one and adds exactly one occurrence of Id. Room for the new
   --  node is explicit: a 16-position model cannot represent 17 nodes.
   procedure Lemma_Append_Walk
     (Before, After : Task_Links;
      Start         : Optional_Task_Id;
      Tail          : Task_Id;
      Id            : Task_Id)
   with Ghost,
     Pre => Start /= No_Task
       and then Chain_Terminates (Before, Start)
       and then Chain_Length (Before, Start) < Max_Tasks
       and then Before (Tail) = No_Task
       and then Chain_Occurrences (Before, Start, Tail) = 1
       and then Chain_Occurrences (Before, Start, Id) = 0
       and then Id /= Tail
       and then After (Tail) = To_Optional (Id)
       and then After (Id) = No_Task
       and then (for all T in Task_Id =>
                   (if T /= Tail then Before (T) = After (T))),
     Post => Chain_Terminates (After, Start)
       and then Chain_Length (After, Start) =
                  Chain_Length (Before, Start) + 1
        and then Follow (After, Start, Chain_Length (Before, Start)) =
                   To_Optional (Id)
       and then Chain_Occurrences (After, Start, Id) = 1
        and then Chain_Occurrences (After, Start, Tail) = 1
        and then (for all Other in Task_Id =>
                    (if Other /= Id then
                       Chain_Occurrences (After, Start, Other) =
                         Chain_Occurrences (Before, Start, Other))),
     Subprogram_Variant => (Decreases => Chain_Length (Before, Start));

   procedure Lemma_Append_At_Tail
     (Before, After : Task_Links;
      Head          : Optional_Task_Id;
      Tail          : Task_Id;
      Id            : Task_Id)
   with Ghost,
     Pre => Head /= No_Task
       and then Chain_Terminates (Before, Head)
       and then Chain_Length (Before, Head) < Max_Tasks
       and then Before (Tail) = No_Task
       and then Chain_Occurrences (Before, Head, Tail) = 1
       and then Chain_Occurrences (Before, Head, Id) = 0
       and then Id /= Tail
       and then After (Tail) = To_Optional (Id)
       and then After (Id) = No_Task
       and then (for all T in Task_Id =>
                   (if T /= Tail then Before (T) = After (T))),
     Post => Chain_Terminates (After, Head)
       and then Chain_Length (After, Head) = Chain_Length (Before, Head) + 1
        and then Follow (After, Head, Chain_Length (Before, Head)) =
                   To_Optional (Id)
       and then Chain_Occurrences (After, Head, Id) = 1
        and then Chain_Occurrences (After, Head, Tail) = 1
        and then (for all Other in Task_Id =>
                    (if Other /= Id then
                       Chain_Occurrences (After, Head, Other) =
                         Chain_Occurrences (Before, Head, Other)));

   procedure Lemma_Follow_Priority
     (S : Scheduler; Head : Optional_Task_Id; P : Priority; Steps : Natural)
   with Ghost,
     Pre => Steps <= Max_Tasks and then Next_Edges_Valid (S)
       and then (if Head /= No_Task then
                   S.States (To_Task_Id (Head)) = Ready
                   and then S.Priorities (To_Task_Id (Head)) = P),
     Post => (if Follow (S.Next, Head, Steps) /= No_Task then
                S.States (To_Task_Id (Follow (S.Next, Head, Steps))) = Ready
                and then
                S.Priorities (To_Task_Id (Follow (S.Next, Head, Steps))) = P),
     Subprogram_Variant => (Decreases => Steps);

   --  Priority consistency, not injectivity alone, separates queues.
   --  Without it, two priority slots could contain the same head.
   procedure Lemma_Distinct_Priorities_Disjoint
     (S : Scheduler; P, Q : Priority; T : Task_Id)
   with Ghost,
     Pre => Endpoint_Ready_Valid (S) and then Next_Edges_Valid (S)
       and then P /= Q,
     Post => (if Chain_Occurrences (S.Next, S.Heads (P), T) > 0 then
                 Chain_Occurrences (S.Next, S.Heads (Q), T) = 0);

   procedure Lemma_Occurrence_Validity
     (S : Scheduler; P : Priority; T : Task_Id; Fuel : Natural)
   with Ghost,
     Pre => Fuel <= Max_Tasks
       and then Endpoint_Ready_Valid (S) and then Next_Edges_Valid (S),
     Post => (if Occurrence_Prefix (S.Next, S.Heads (P), T, Fuel) > 0
              then S.States (T) = Ready and then S.Priorities (T) = P),
     Subprogram_Variant => (Decreases => Fuel);

   --  Head-reachable termination alone admits disconnected cycles.
   --  Excluding disconnected Ready cycles also needs stable membership;
   --  Nonready_Unlinked excludes outgoing edges of non-Ready tasks.
   function All_Ready_Chains_Terminate (S : Scheduler) return Boolean
   is (for all P in Priority => Chain_Terminates (S.Next, S.Heads (P)));

   function Occurrences_By_Priority
     (S : Scheduler; Id : Task_Id) return Ready_Length_Map
   with Ghost,
     Post => (for all P in Priority =>
                Occurrences_By_Priority'Result (P) =
                  Chain_Occurrences (S.Next, S.Heads (P), Id));

   function Occurrences_By_Priority
     (S : Scheduler; Id : Task_Id) return Ready_Length_Map
   is
     ((0 => Chain_Occurrences (S.Next, S.Heads (0), Id),
       1 => Chain_Occurrences (S.Next, S.Heads (1), Id),
       2 => Chain_Occurrences (S.Next, S.Heads (2), Id),
       3 => Chain_Occurrences (S.Next, S.Heads (3), Id),
       4 => Chain_Occurrences (S.Next, S.Heads (4), Id),
       5 => Chain_Occurrences (S.Next, S.Heads (5), Id),
       6 => Chain_Occurrences (S.Next, S.Heads (6), Id),
       7 => Chain_Occurrences (S.Next, S.Heads (7), Id)));

   function Ready_Lengths (S : Scheduler) return Ready_Length_Map
   with Ghost,
     Post => (for all P in Priority =>
                Ready_Lengths'Result (P) = Chain_Length (S.Next, S.Heads (P)));

   function Ready_Lengths (S : Scheduler) return Ready_Length_Map
   is
     ((0 => Chain_Length (S.Next, S.Heads (0)),
       1 => Chain_Length (S.Next, S.Heads (1)),
       2 => Chain_Length (S.Next, S.Heads (2)),
       3 => Chain_Length (S.Next, S.Heads (3)),
       4 => Chain_Length (S.Next, S.Heads (4)),
       5 => Chain_Length (S.Next, S.Heads (5)),
       6 => Chain_Length (S.Next, S.Heads (6)),
       7 => Chain_Length (S.Next, S.Heads (7))));

   function Sum (Values : Ready_Length_Map) return Global_Occurrence_Count
   is (Values (0) + Values (1) + Values (2) + Values (3)
       + Values (4) + Values (5) + Values (6) + Values (7))
   with Ghost;

   function Ready_Occurrences (S : Scheduler; Id : Task_Id)
     return Global_Occurrence_Count
   is (Sum (Occurrences_By_Priority (S, Id)));

   function Ready_Contains (S : Scheduler; Id : Task_Id) return Boolean
   is (Ready_Occurrences (S, Id) > 0);

   function Total_Ready_Chain_Length (S : Scheduler)
     return Global_Occurrence_Count
   is (Sum (Ready_Lengths (S)));

   function Copy_Ready_Occurrences (S : Scheduler) return Ready_Occurrence_Map
   is
     ((1  => Ready_Occurrences (S, 1),
       2  => Ready_Occurrences (S, 2),
       3  => Ready_Occurrences (S, 3),
       4  => Ready_Occurrences (S, 4),
       5  => Ready_Occurrences (S, 5),
       6  => Ready_Occurrences (S, 6),
       7  => Ready_Occurrences (S, 7),
       8  => Ready_Occurrences (S, 8),
       9  => Ready_Occurrences (S, 9),
       10 => Ready_Occurrences (S, 10),
       11 => Ready_Occurrences (S, 11),
       12 => Ready_Occurrences (S, 12),
       13 => Ready_Occurrences (S, 13),
       14 => Ready_Occurrences (S, 14),
       15 => Ready_Occurrences (S, 15),
       16 => Ready_Occurrences (S, 16)));

   function Copy_Ready_Lengths (S : Scheduler) return Ready_Length_Map
   is (Ready_Lengths (S));

   function Tails_Reachable (S : Scheduler) return Boolean
   is (for all P in Priority =>
         (if S.Heads (P) = No_Task then S.Tails (P) = No_Task
          else S.Tails (P) /= No_Task
            and then Chain_Occurrences
              (S.Next, S.Heads (P), To_Task_Id (S.Tails (P))) = 1));

   function All_Reachable_Tasks_Ready (S : Scheduler) return Boolean
   is (for all P in Priority =>
         (for all T in Task_Id =>
            (if Chain_Occurrences (S.Next, S.Heads (P), T) > 0
             then S.States (T) = Ready)));

   function All_Reachable_Priorities_Valid (S : Scheduler) return Boolean
   is (for all P in Priority =>
         (for all T in Task_Id =>
            (if Chain_Occurrences (S.Next, S.Heads (P), T) > 0
             then S.Priorities (T) = P)));

   function Ready_Membership_Valid (S : Scheduler) return Boolean
   is (for all T in Task_Id =>
         Ready_Occurrences (S, T) = (if S.States (T) = Ready then 1 else 0));

   function Ready_Chain_Count_Valid (S : Scheduler) return Boolean
   is (Total_Ready_Chain_Length (S) = S.Ready_Count);

   function Indexed_Reachability_Model_Valid (S : Scheduler) return Boolean
   is (All_Ready_Chains_Terminate (S)
       and then Tails_Reachable (S)
       and then All_Reachable_Tasks_Ready (S)
       and then All_Reachable_Priorities_Valid (S)
       and then Ready_Membership_Valid (S)
       and then Ready_Chain_Count_Valid (S));

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
