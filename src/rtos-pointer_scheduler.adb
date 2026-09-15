package body RTOS.Pointer_Scheduler
  with SPARK_Mode => On
is

   function Ready_Lengths (S : Scheduler) return Length_Map is
      Result : Length_Map := (others => To_Big_Integer (0));
   begin
      for P in Priority loop
         Result (P) := List_Length (S.Heads (P));
      end loop;
      return Result;
   end Ready_Lengths;

   function Occurrences_By_Priority (S : Scheduler; Id : Task_Id)
     return Length_Map
   is
      Result : Length_Map := (others => To_Big_Integer (0));
   begin
      for P in Priority loop
         Result (P) := Occurrences (S.Heads (P), Id);
      end loop;
      return Result;
   end Occurrences_By_Priority;

   procedure Lemma_Free_Node_Available (S : Scheduler) is
   begin
      null;
   end Lemma_Free_Node_Available;

   procedure Lemma_Nonempty_List_Length (Head : access constant Ready_Node) is
   begin
      null;
   end Lemma_Nonempty_List_Length;

   procedure Lemma_Empty_List_Length (Head : access constant Ready_Node) is
   begin
      null;
   end Lemma_Empty_List_Length;

   procedure Find_Highest_Ready
     (S        : Scheduler;
      Found    : out Boolean;
      Selected : out Priority)
   is
   begin
      Found := False;
      Selected := Priority'First;

      for P in reverse Priority loop
         if S.Heads (P) /= null then
            Lemma_Nonempty_List_Length (S.Heads (P));
            Found := True;
            Selected := P;
            return;
         else
            Lemma_Empty_List_Length (S.Heads (P));
         end if;
      end loop;
   end Find_Highest_Ready;

   procedure Lemma_Search_No_Ready_Above
     (S        : Scheduler;
      Found    : Boolean;
      Selected : Priority;
      Bound    : Priority)
   is
   begin
      null;
   end Lemma_Search_No_Ready_Above;

   function Copy_Ready_Occurrences (S : Scheduler)
     return Ready_Occurrence_Map
   is
      Result : Ready_Occurrence_Map := (others => To_Big_Integer (0));
   begin
      for T in Task_Id loop
         Result (T) := Ready_Occurrences (S, T);
         pragma Loop_Invariant
           (for all U in Task_Id =>
              (if U <= T then Result (U) = Ready_Occurrences (S, U)));
      end loop;
      return Result;
   end Copy_Ready_Occurrences;

   procedure Lemma_Null_List_Occurrences (L : access constant Ready_Node) is
   begin
      null;
   end Lemma_Null_List_Occurrences;

   procedure Lemma_Remove_Head_Occurrences
     (Head : access constant Ready_Node;
      Id   : Task_Id)
   is
   begin
      null;
   end Lemma_Remove_Head_Occurrences;

   procedure Lemma_All_At_Priority_Tail
     (Head       : access constant Ready_Node;
      P          : Priority;
      Priorities : Task_Priorities)
   is
   begin
      null;
   end Lemma_All_At_Priority_Tail;

   procedure Lemma_Priority_Implies_Valid_Ids
     (L          : access constant Ready_Node;
      P          : Priority;
      Priorities : Task_Priorities)
   is
   begin
      if L /= null then
         Lemma_Priority_Implies_Valid_Ids (L.Next, P, Priorities);
      end if;
   end Lemma_Priority_Implies_Valid_Ids;

   procedure Lemma_Occurrence_Implies_Priority
     (L          : access constant Ready_Node;
      T          : Task_Id;
      P          : Priority;
      Priorities : Task_Priorities)
   is
   begin
      if L /= null then
         if L.Id = To_Optional (T) then
            null;
         else
            Lemma_Occurrence_Implies_Priority (L.Next, T, P, Priorities);
         end if;
      end if;
   end Lemma_Occurrence_Implies_Priority;

   procedure Lemma_Empty_Heads_Membership (S : Scheduler) is
   begin
      for P in Priority loop
         Lemma_Null_List_Occurrences (S.Heads (P));
         pragma Loop_Invariant
           (for all Q in Priority =>
              (if Q <= P then
                 All_At_Priority (S.Heads (Q), Q, S.Priorities)
                 and then All_Ready_Ids_Valid (S.Heads (Q))));
      end loop;
   end Lemma_Empty_Heads_Membership;

   procedure Lemma_Ready_Task_At_Configured_Priority
     (S : Scheduler;
      T : Task_Id)
   is
      Prio : constant Priority := S.Priorities (T);
   begin
      for Q in Priority loop
         if Occurrences (S.Heads (Q), T) > 0 then
            Lemma_Occurrence_Implies_Priority
              (S.Heads (Q), T, Q, S.Priorities);
            pragma Assert (Q = Prio);
         end if;
         pragma Loop_Invariant
           (for all R in Priority =>
              (if R <= Q and then R /= Prio then
                 Occurrences (S.Heads (R), T) = To_Big_Integer (0)));
      end loop;
   end Lemma_Ready_Task_At_Configured_Priority;

   procedure Lemma_Head_Identity_Ready
     (S : Scheduler;
      P : Priority)
   is
      Id : Task_Id;
   begin
      Lemma_All_At_Priority_Tail (S.Heads (P), P, S.Priorities);
      Id := To_Task_Id (S.Heads (P).Id);
      pragma Assert (S.Priorities (Id) = P);
      pragma Assert (Occurrences (S.Heads (P), Id) > 0);
      pragma Assert (Ready_Occurrences (S, Id) > 0);
      pragma Assert (S.States (Id) = RTOS.Types.Ready);
      Lemma_Ready_Task_At_Configured_Priority (S, Id);
   end Lemma_Head_Identity_Ready;

   procedure Lemma_Unfold_Ready_Occurrences
     (S : Scheduler;
      T : Task_Id)
   is
   begin
      null;
   end Lemma_Unfold_Ready_Occurrences;

   procedure Lemma_Highest_Ready_Is_Greatest_Priority
     (S        : Scheduler;
      Selected : Priority)
   is
   begin
      for T in Task_Id loop
         if S.States (T) = RTOS.Types.Ready then
            Lemma_Ready_Task_At_Configured_Priority (S, T);
            pragma Assert (S.Heads (S.Priorities (T)) /= null);
            pragma Assert (S.Priorities (T) <= Selected);
         end if;
         pragma Loop_Invariant
           (for all U in Task_Id =>
              (if U <= T and then S.States (U) = RTOS.Types.Ready then
                 S.Priorities (U) <= Selected));
      end loop;
   end Lemma_Highest_Ready_Is_Greatest_Priority;

   function Contents (L : access constant Ready_Node) return Occurrence_Map
   is
      Result : Occurrence_Map := (others => To_Big_Integer (0));
   begin
      for Id in Task_Id loop
         Result (Id) := Occurrences (L, Id);
      end loop;
      return Result;
   end Contents;

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

   procedure Remove_Ready_Head_At_Priority
     (Head       : in out Node_Access;
      Node       : out Node_Access;
      P          : Priority;
      Priorities : Task_Priorities)
   is
   begin
      Lemma_All_At_Priority_Tail (Head, P, Priorities);
      Lemma_Priority_Implies_Valid_Ids (Head, P, Priorities);
      pragma Assert (All_At_Priority (Head.Next, P, Priorities));
      Node := Head;
      Head := Node.Next;
      Node.Next := null;
   end Remove_Ready_Head_At_Priority;

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
         pragma Loop_Invariant
           (List_Length (Head) = To_Big_Integer (Count));
         pragma Loop_Invariant (All_Free (Head));

         Head := new Ready_Node'(Id => No_Task, Next => Head);
         Count := Count + 1;
      end loop;
   end Allocate_Pool;

   procedure Append_Ready_Tail
     (Head       : in out Node_Access;
      Node       : in out Node_Access;
      P          : Priority;
      Priorities : Task_Priorities)
   is
      Length_Before : constant Big_Natural := List_Length (Head) with Ghost;
      Inserted : constant Optional_Task_Id := Node.Id with Ghost;
      Contents_Before : constant Occurrence_Map := Contents (Head)
        with Ghost;
   begin
      Lemma_Priority_Implies_Valid_Ids (Head, P, Priorities);

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
               pragma Loop_Invariant
                 (if Contains_Id
                      (At_End (Cursor), To_Task_Id (Inserted))
                  then Contains_Id (At_End (Head), To_Task_Id (Inserted)));
               pragma Loop_Invariant
                 (for all Id in Task_Id =>
                   Occurrences (At_End (Head), Id) = Contents_Before (Id)
                     - Occurrences (Cursor, Id)
                     + Occurrences (At_End (Cursor), Id));
               pragma Loop_Invariant
                 (List_Length (At_End (Head)) = Length_Before
                    - List_Length (Cursor) + List_Length (At_End (Cursor)));
               pragma Loop_Invariant (All_Ready_Ids_Valid (Cursor));
               pragma Loop_Invariant
                 (All_At_Priority (Cursor, P, Priorities));
               pragma Loop_Invariant
                 (if All_Ready_Ids_Valid (At_End (Cursor))
                  then All_Ready_Ids_Valid (At_End (Head)));
               pragma Loop_Invariant
                 (if All_At_Priority (At_End (Cursor), P, Priorities)
                  then All_At_Priority (At_End (Head), P, Priorities));
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

      Lemma_Empty_Heads_Membership (S);
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

      pragma Assert (Ready_Occurrences (S, Id) = To_Big_Integer (0));
      Acquire_Node (S.Free_Head, Node);
      Node.Id := To_Optional (Id);
      Append_Ready_Tail (S.Heads (Prio), Node, Prio, Keep_Prio);

      S.Current := Keep_Curr;
      S.Priorities := Keep_Prio;
      S.States := Keep_States;
      S.Free_Node_Count := Free_Count - 1;
      S.Ready_Node_Count := Ready_Count + 1;
      S.Initialized := Keep_Init;
   end Make_Ready;

   procedure Block (S : in out Scheduler; Id : Task_Id) is
   begin
      S.States (Id) := Blocked;
      S.Current := No_Task;
   end Block;

   procedure Yield (S : in out Scheduler) is
      Id          : constant Task_Id := To_Task_Id (S.Current);
      Prio        : constant Priority := S.Priorities (Id);
      Node        : Node_Access;
      Free_Count  : constant Node_Count := S.Free_Node_Count;
      Ready_Count : constant Node_Count := S.Ready_Node_Count;
      Keep_Init   : constant Boolean := S.Initialized;
      Keep_Prio   : constant Task_Priorities := S.Priorities;
      Keep_States : Task_State_Map := S.States;
   begin
      Keep_States (Id) := RTOS.Types.Ready;

      Lemma_Free_Node_Available (S);
      pragma Assert (Ready_Occurrences (S, Id) = To_Big_Integer (0));
      Acquire_Node (S.Free_Head, Node);
      Node.Id := To_Optional (Id);
      Append_Ready_Tail (S.Heads (Prio), Node, Prio, Keep_Prio);

      S.Current := No_Task;
      S.Priorities := Keep_Prio;
      S.States := Keep_States;
      S.Free_Node_Count := Free_Count - 1;
      S.Ready_Node_Count := Ready_Count + 1;
      S.Initialized := Keep_Init;

      pragma Assert (S.Current = No_Task);
      pragma Assert (S.States (Id) = RTOS.Types.Ready);
      pragma Assert (Ready_Occurrences (S, Id) = To_Big_Integer (1));
      pragma Assert (Scheduler_Valid (S));

      Select_Next (S);
   end Yield;

   procedure Select_Next (S : in out Scheduler) is
      Found    : Boolean;
      Selected : Priority;
      Node     : Node_Access;
      Chosen   : Task_Id;
      Free_Count  : constant Node_Count := S.Free_Node_Count;
      Ready_Count : constant Node_Count := S.Ready_Node_Count;
      Keep_Init   : constant Boolean := S.Initialized;
      Keep_Prio   : constant Task_Priorities := S.Priorities;
      Keep_States : Task_State_Map := S.States;
      Occ_Before  : constant Ready_Occurrence_Map :=
        Copy_Ready_Occurrences (S) with Ghost;
   begin
      if Ready_Count = 0 then
         return;
      end if;

      Find_Highest_Ready (S, Found, Selected);
      pragma Assert (Found);
      pragma Assert (S.Heads (Selected) /= null);
      Lemma_Highest_Ready_Is_Greatest_Priority (S, Selected);
      Lemma_Head_Identity_Ready (S, Selected);
      Chosen := To_Task_Id (S.Heads (Selected).Id);
      Lemma_Unfold_Ready_Occurrences (S, Chosen);
      Lemma_Remove_Head_Occurrences (S.Heads (Selected), Chosen);
      pragma Assert (Occ_Before (Chosen) = To_Big_Integer (1));
      pragma Assert (Occurrences (S.Heads (Selected), Chosen) =
                       To_Big_Integer (1));

      Remove_Ready_Head_At_Priority
        (S.Heads (Selected), Node, Selected, S.Priorities);
      pragma Assert (Has_Task (Node.Id));
      pragma Assert (To_Task_Id (Node.Id) = Chosen);
      pragma Assert (S.Priorities (Chosen) = Selected);
      Lemma_Unfold_Ready_Occurrences (S, Chosen);
      pragma Assert (Ready_Occurrences (S, Chosen) = To_Big_Integer (0));
      Keep_States (Chosen) := Running;

      Release_Node (S.Free_Head, Node);

      S.Current := To_Optional (Chosen);
      S.Priorities := Keep_Prio;
      S.States := Keep_States;
      S.Free_Node_Count := Free_Count + 1;
      S.Ready_Node_Count := Ready_Count - 1;
      S.Initialized := Keep_Init;

      pragma Assert (S.Current = To_Optional (Chosen));
      pragma Assert (S.States (Chosen) = Running);
      pragma Assert (S.Priorities (Chosen) = Selected);
      pragma Assert (Ready_Occurrences (S, Chosen) = To_Big_Integer (0));
      pragma Assert (Occ_Before (Chosen) = To_Big_Integer (1));
   end Select_Next;

   procedure Schedule (S : in out Scheduler) is
      Id          : Task_Id;
      Prio        : Priority;
      Found       : Boolean;
      Highest     : Priority;
      Node        : Node_Access;
      Free_Count  : Node_Count;
      Ready_Count : Node_Count;
      Keep_Init   : Boolean;
      Keep_Prio   : Task_Priorities;
      Keep_States : Task_State_Map;
   begin
      if S.Current = No_Task then
         Select_Next (S);
         return;
      end if;

      Id := To_Task_Id (S.Current);
      Prio := S.Priorities (Id);
      Find_Highest_Ready (S, Found, Highest);
      Lemma_Search_No_Ready_Above (S, Found, Highest, Prio);

      if not Found or else Highest <= Prio then
         pragma Assert (No_Ready_Above (Copy_Ready_Lengths (S), Prio));
         pragma Assert (S.Current = To_Optional (Id));
         return;
      end if;

      pragma Assert (Found);
      pragma Assert (Highest > Prio);
      pragma Assert (List_Length (S.Heads (Highest)) > 0);
      pragma Assert (not No_Ready_Above (Copy_Ready_Lengths (S), Prio));

      Free_Count := S.Free_Node_Count;
      Ready_Count := S.Ready_Node_Count;
      Keep_Init := S.Initialized;
      Keep_Prio := S.Priorities;
      Keep_States := S.States;
      Keep_States (Id) := RTOS.Types.Ready;

      Lemma_Free_Node_Available (S);
      pragma Assert (Ready_Occurrences (S, Id) = To_Big_Integer (0));
      Acquire_Node (S.Free_Head, Node);
      Node.Id := To_Optional (Id);
      Append_Ready_Tail (S.Heads (Prio), Node, Prio, Keep_Prio);

      S.Current := No_Task;
      S.Priorities := Keep_Prio;
      S.States := Keep_States;
      S.Free_Node_Count := Free_Count - 1;
      S.Ready_Node_Count := Ready_Count + 1;
      S.Initialized := Keep_Init;

      pragma Assert (S.Current = No_Task);
      pragma Assert (S.States (Id) = RTOS.Types.Ready);
      pragma Assert (Ready_Occurrences (S, Id) = To_Big_Integer (1));
      pragma Assert (Ready_Membership_Valid (S));
      pragma Assert (All_Ready_Priorities_Valid (S));
      pragma Assert (Scheduler_Valid (S));

      Select_Next (S);
   end Schedule;

end RTOS.Pointer_Scheduler;
