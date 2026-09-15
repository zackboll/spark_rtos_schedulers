package body RTOS.Pointer_Scheduler
  with SPARK_Mode => On
is

   procedure Prepend_Node
     (Head : in out Node_Access;
      Node : in out Node_Access)
   is
   begin
      Node.Next := Head;
      Head := Node;
      Node := null;
   end Prepend_Node;

   procedure Remove_Ready_Head
     (Head : in out Node_Access;
      Node : out Node_Access)
   is
   begin
      Node := Head;
      Head := Node.Next;
      Node.Next := null;
   end Remove_Ready_Head;

   procedure Acquire_Node
     (Head : in out Node_Access;
      Node : out Node_Access)
   is
   begin
      Remove_Ready_Head (Head, Node);
      Node.Id := No_Task;
   end Acquire_Node;

   procedure Release_Node
     (Head : in out Node_Access;
      Node : in out Node_Access)
   is
   begin
      Node.Id := No_Task;
      Prepend_Node (Head, Node);
   end Release_Node;

   procedure Allocate_Pool
     (Head  : in out Node_Access;
      Count : out Node_Count)
   is
   begin
      Count := 0;

      for I in Task_Id loop
         pragma Loop_Invariant
           (Count = Natural (I - Task_Id'First));
         pragma Loop_Invariant (Count < Max_Tasks);
         pragma Loop_Invariant ((Count = 0) = (Head = null));

         Head := new Ready_Node'(Id => No_Task, Next => Head);
         Count := Count + 1;
      end loop;
   end Allocate_Pool;

   procedure Append_Ready_Tail
     (Head : in out Node_Access;
      Node : in out Node_Access)
   is
   begin
      if Head = null then
         Head := Node;
         Node := null;
      else
         declare
            Cursor : access Ready_Node := Head;
         begin
            while Cursor.Next /= null loop
               pragma Loop_Variant (Structural => Cursor);
               pragma Loop_Invariant (Cursor /= null);
               Cursor := Cursor.Next;
            end loop;

            Cursor.Next := Node;
            Node := null;
         end;
      end if;
   end Append_Ready_Tail;

   procedure Initialize
     (S          : in out Scheduler;
      Priorities : Task_Priorities)
   is
      Free  : Node_Access := null;
      Count : Node_Count;
   begin
      --  Allocate onto a local owner. Is_Virgin still holds, so taking
      --  the pool into S.Free_Head cannot leak a previous chain.
      Allocate_Pool (Free, Count);

      S.Current := No_Task;
      S.Priorities := Priorities;
      S.States := (others => Dormant);
      S.Ready_Node_Count := 0;
      S.Free_Node_Count := Count;
      S.Free_Head := Free;
      S.Initialized := True;
   end Initialize;

   procedure Make_Ready (S : in out Scheduler; Id : Task_Id) is
      Node        : Node_Access;
      Prio        : constant Priority := S.Priorities (Id);
      Free_Count  : constant Node_Count := S.Free_Node_Count;
      Ready_Count : constant Node_Count := S.Ready_Node_Count;
      Keep_Init   : constant Boolean := S.Initialized;
      Keep_Curr   : constant Optional_Task_Id := S.Current;
      Keep_Prio   : constant Task_Priorities := S.Priorities;
      Keep_States : Task_State_Map := S.States;
   begin
      --  Preserve scalar state explicitly while the list primitives
      --  transfer ownership through the two selected roots. The
      --  snapshots also make the accounting updates explicit.
      Keep_States (Id) := RTOS.Types.Ready;

      Acquire_Node (S.Free_Head, Node);
      Node.Id := To_Optional (Id);
      Append_Ready_Tail (S.Heads (Prio), Node);

      S.Current := Keep_Curr;
      S.Priorities := Keep_Prio;
      S.States := Keep_States;
      S.Free_Node_Count := Free_Count - 1;
      S.Ready_Node_Count := Ready_Count + 1;
      S.Initialized := Keep_Init;
   end Make_Ready;

   procedure Block (S : in out Scheduler; Id : Task_Id) is
      Keep : constant Boolean := S.Initialized;
   begin
      --  Skeleton: ready-list removal is not implemented yet.
      S.States (Id) := Blocked;
      if S.Current = To_Optional (Id) then
         S.Current := No_Task;
      end if;
      S.Initialized := Keep;
   end Block;

   procedure Yield (S : in out Scheduler) is
      Keep : constant Boolean := S.Initialized;
   begin
      --  Skeleton: round-robin requeue is not implemented yet.
      if Has_Task (S.Current) then
         S.States (To_Task_Id (S.Current)) := Ready;
         S.Current := No_Task;
      end if;
      S.Initialized := Keep;
   end Yield;

   procedure Select_Next (S : in out Scheduler) is
      Keep : constant Boolean := S.Initialized;
   begin
      --  Skeleton: highest-priority head removal is not implemented yet.
      S.Current := No_Task;
      S.Initialized := Keep;
   end Select_Next;

   procedure Schedule (S : in out Scheduler) is
   begin
      --  Skeleton: forwards to the Select_Next skeleton.
      Select_Next (S);
   end Schedule;

end RTOS.Pointer_Scheduler;
