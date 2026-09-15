with RTOS.Types;

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
--  Make_Ready is wired to acquire + tail-append. Block, Yield,
--  Select_Next, and Schedule remain skeleton implementations.

package RTOS.Pointer_Scheduler
  with SPARK_Mode => On
is

   pragma Unevaluated_Use_Of_Old (Allow);

   use RTOS.Types;

   subtype Node_Count is Natural range 0 .. Max_Tasks;

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

   function Has_Free_Node (S : Scheduler) return Boolean
     with Ghost;

   function Free_Nodes (S : Scheduler) return Node_Count
     with Ghost;

   function Ready_Nodes (S : Scheduler) return Node_Count
     with Ghost;

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
     and then (for all Id in Task_Id => State_Of (S, Id) = Dormant);

   --  Acquire a free node, assign Id, and append at the tail of the
   --  ready list for Id's priority. No allocation is performed.
   procedure Make_Ready (S : in out Scheduler; Id : Task_Id)
   with
     Pre  => Is_Initialized (S)
     and then State_Of (S, Id) /= Ready
     and then State_Of (S, Id) /= Running
     and then Has_Free_Node (S)
     and then Free_Nodes (S) > 0
     and then Ready_Nodes (S) < Max_Tasks,
     Post => Is_Initialized (S)
     and then State_Of (S, Id) = Ready
     and then Free_Nodes (S) = Free_Nodes (S)'Old - 1
     and then Ready_Nodes (S) = Ready_Nodes (S)'Old + 1;

   --  Temporary representation-preserving no-ops until full pointer
   --  transitions are implemented. No scalar, list, or count is changed.
   --  Block does not yet detach a ready-list node.
   procedure Block (S : in out Scheduler; Id : Task_Id)
   with
     Pre  => Is_Initialized (S),
     Post => Is_Initialized (S)
     and then Current_Task (S) = Current_Task (S)'Old;

   --  Skeleton: does not yet requeue a running task.
   procedure Yield (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S),
     Post => Is_Initialized (S)
     and then Current_Task (S) = Current_Task (S)'Old;

   --  Skeleton: does not yet remove a ready-list head.
   procedure Select_Next (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S),
     Post => Is_Initialized (S)
     and then Current_Task (S) = Current_Task (S)'Old;

   --  Skeleton: forwards to Select_Next only.
   procedure Schedule (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S),
     Post => Is_Initialized (S)
     and then Current_Task (S) = Current_Task (S)'Old;

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

   function Has_Free_Node (S : Scheduler) return Boolean
   is (S.Free_Head /= null);

   function Free_Nodes (S : Scheduler) return Node_Count
   is (S.Free_Node_Count);

   function Ready_Nodes (S : Scheduler) return Node_Count
   is (S.Ready_Node_Count);

   --  Allocate Max_Tasks nodes onto Head. Head is a local owner so the
   --  scheduler record is not part of the allocation-loop VCs.
   procedure Allocate_Pool
     (Head  : in out Node_Access;
      Count : out Node_Count)
   with
     Pre  => Head = null,
     Post => Head /= null and then Count = Max_Tasks;

   --  O(1). Move a detached node onto Head.
   procedure Prepend_Node
     (Head : in out Node_Access;
      Node : in out Node_Access)
   with
     Pre  => Node /= null and then Node.Next = null,
     Post => Node = null and then Head /= null;

   --  O(1). Move the list head into Node and detach it.
   procedure Remove_Ready_Head
     (Head : in out Node_Access;
      Node : out Node_Access)
   with
     Pre  => Head /= null,
     Post => Node /= null and then Node.Next = null;

   --  O(1). Move Head's first node into Node, detach it, and mark it
   --  free. Make_Ready passes S.Free_Head as Head.
   procedure Acquire_Node
     (Head : in out Node_Access;
      Node : out Node_Access)
   with
     Pre  => Head /= null,
     Post => Node /= null
     and then Node.Next = null
     and then Node.Id = No_Task;

   --  O(1). Clear a detached node and move it onto Head. Inverse of
   --  Acquire_Node; Make_Ready does not need it yet.
   procedure Release_Node
     (Head : in out Node_Access;
      Node : in out Node_Access)
   with
     Pre  => Node /= null and then Node.Next = null,
     Post => Node = null and then Head /= null;

   --  O(N). Move a detached node to the tail of Head. Empty lists take
   --  the node as the new head. Nonempty lists are borrowed with an
   --  anonymous access cursor; there is no stored Tail.
   procedure Append_Ready_Tail
     (Head : in out Node_Access;
      Node : in out Node_Access)
   with
     Pre  => Node /= null and then Node.Next = null,
     Post => Node = null and then Head /= null;

end RTOS.Pointer_Scheduler;
