package body RTOS.Indexed_Scheduler
  with SPARK_Mode => On
is

   procedure Lemma_Follow_Null
     (Links : Task_Links; Steps : Natural)
   is
   begin
      if Steps > 0 then
         Lemma_Follow_Null (Links, Steps - 1);
      end if;
   end Lemma_Follow_Null;

   procedure Lemma_Follow_Compose
     (Links : Task_Links;
      Start : Optional_Task_Id;
      A, B  : Natural)
   is
   begin
      if A > 0 then
         if Start = No_Task then
            Lemma_Follow_Null (Links, A);
            Lemma_Follow_Null (Links, A + B);
            Lemma_Follow_Null (Links, B);
         else
            Lemma_Follow_Compose
              (Links, Links (To_Task_Id (Start)), A - 1, B);
         end if;
      end if;
   end Lemma_Follow_Compose;

   procedure Lemma_Follow_After_Null
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      K     : Natural;
      Steps : Natural)
   is
   begin
      Lemma_Follow_Compose (Links, Head, K, Steps - K);
      Lemma_Follow_Null (Links, Steps - K);
   end Lemma_Follow_After_Null;

   procedure Lemma_Follow_Frame
     (Before, After : Task_Links;
      Start         : Optional_Task_Id;
      Changed       : Task_Id;
      Steps         : Natural)
   is
   begin
      if Steps > 0 and then Start /= No_Task then
         Lemma_Follow_Frame
           (Before, After, Before (To_Task_Id (Start)), Changed, Steps - 1);
      end if;
   end Lemma_Follow_Frame;

   procedure Lemma_Length_Prefix_Unfold
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Fuel  : Natural)
   is
   begin
      if Fuel > 0 then
         Lemma_Length_Prefix_Unfold (Links, Head, Fuel - 1);
      end if;
   end Lemma_Length_Prefix_Unfold;

   procedure Lemma_Occurrence_Prefix_Unfold
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Id    : Task_Id;
      Fuel  : Natural)
   is
   begin
      if Fuel > 0 then
         Lemma_Occurrence_Prefix_Unfold (Links, Head, Id, Fuel - 1);
      end if;
   end Lemma_Occurrence_Prefix_Unfold;

   procedure Lemma_Empty_Chain
     (Links : Task_Links; Id : Task_Id)
   is
   begin
      Lemma_Follow_Null (Links, Max_Tasks);
      pragma Assert (Id in Task_Id);
   end Lemma_Empty_Chain;

   procedure Lemma_Singleton_Chain
     (Links : Task_Links; Id : Task_Id)
   is
   begin
      Lemma_Follow_Null (Links, Max_Tasks - 1);
      Lemma_Follow_Compose (Links, To_Optional (Id), 1, Max_Tasks - 1);
   end Lemma_Singleton_Chain;

   procedure Lemma_Length_Frame
     (Before, After : Task_Links;
      Head          : Optional_Task_Id;
      Changed       : Task_Id;
      Fuel          : Natural)
   is
   begin
      Lemma_Follow_Frame (Before, After, Head, Changed, Fuel);
      if Fuel > 0 then
         Lemma_Length_Frame (Before, After, Head, Changed, Fuel - 1);
      end if;
   end Lemma_Length_Frame;

   procedure Lemma_Occurrence_Frame
     (Before, After : Task_Links;
      Head          : Optional_Task_Id;
      Changed       : Task_Id;
      Id            : Task_Id;
      Fuel          : Natural)
   is
   begin
      Lemma_Follow_Frame (Before, After, Head, Changed, Fuel);
      if Fuel > 0 then
         Lemma_Occurrence_Frame
           (Before, After, Head, Changed, Id, Fuel - 1);
      end if;
   end Lemma_Occurrence_Frame;

   procedure Lemma_Follow_Shift
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Steps : Natural)
   is
   begin
      Lemma_Follow_Compose (Links, Head, 1, Steps);
   end Lemma_Follow_Shift;

   procedure Lemma_Length_Tail_Prefix
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Fuel  : Natural)
   is
   begin
      if Fuel > 1 then
         Lemma_Follow_Shift (Links, Head, Fuel - 1);
         Lemma_Length_Tail_Prefix (Links, Head, Fuel - 1);
      end if;
   end Lemma_Length_Tail_Prefix;

   procedure Lemma_Occurrence_Tail_Prefix
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Id    : Task_Id;
      Fuel  : Natural)
   is
   begin
      if Fuel > 1 then
         Lemma_Follow_Shift (Links, Head, Fuel - 1);
         Lemma_Occurrence_Tail_Prefix (Links, Head, Id, Fuel - 1);
      end if;
   end Lemma_Occurrence_Tail_Prefix;

   procedure Lemma_Dequeue_Length
     (Links : Task_Links;
      Head  : Optional_Task_Id)
   is
   begin
      Lemma_Follow_Shift (Links, Head, Max_Tasks - 1);
      Lemma_Follow_After_Null
        (Links, Links (To_Task_Id (Head)), Max_Tasks - 1, Max_Tasks);
      Lemma_Length_Tail_Prefix (Links, Head, Max_Tasks);
   end Lemma_Dequeue_Length;

   procedure Lemma_Dequeue_Occurrences
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Id    : Task_Id)
   is
   begin
      Lemma_Follow_Shift (Links, Head, Max_Tasks - 1);
      Lemma_Follow_After_Null
        (Links, Links (To_Task_Id (Head)), Max_Tasks - 1, Max_Tasks);
      Lemma_Occurrence_Tail_Prefix (Links, Head, Id, Max_Tasks);
   end Lemma_Dequeue_Occurrences;

   procedure Lemma_Path_Avoids_Shorter
     (Links   : Task_Links;
      Start   : Optional_Task_Id;
      Changed : Task_Id;
      Fuel    : Natural;
      Less    : Natural)
   is
   begin
      if Fuel > Less then
         Lemma_Path_Avoids_Shorter
           (Links, Start, Changed, Fuel - 1, Less);
      end if;
   end Lemma_Path_Avoids_Shorter;

   procedure Lemma_Zero_Occurrence_Avoids
     (Links   : Task_Links;
      Head    : Optional_Task_Id;
      Changed : Task_Id;
      Fuel    : Natural)
   is
   begin
      if Fuel > 0 and then Head /= No_Task then
         Lemma_Occurrence_Tail_Prefix (Links, Head, Changed, Max_Tasks);
         Lemma_Zero_Occurrence_Avoids
           (Links, Links (To_Task_Id (Head)), Changed, Fuel - 1);
      end if;
   end Lemma_Zero_Occurrence_Avoids;

   procedure Lemma_Unreachable_Link_Frame
     (Before, After : Task_Links;
      Head          : Optional_Task_Id;
      Changed       : Task_Id)
   is
   begin
      Lemma_Zero_Occurrence_Avoids (Before, Head, Changed, Max_Tasks);
      Lemma_Length_Frame (Before, After, Head, Changed, Max_Tasks);
      for K in 0 .. Max_Tasks loop
         Lemma_Path_Avoids_Shorter (Before, Head, Changed, Max_Tasks, K);
         Lemma_Follow_Frame (Before, After, Head, Changed, K);
         pragma Loop_Invariant
           (for all J in 0 .. K =>
              Follow (After, Head, J) = Follow (Before, Head, J));
      end loop;
      for T in Task_Id loop
         Lemma_Occurrence_Frame (Before, After, Head, Changed, T, Max_Tasks);
         pragma Loop_Invariant
           (for all U in Task_Id'First .. T =>
              Chain_Occurrences (After, Head, U) =
                Chain_Occurrences (Before, Head, U));
      end loop;
   end Lemma_Unreachable_Link_Frame;

   procedure Lemma_Terminated_Prefix
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Id    : Task_Id;
      K     : Natural;
      Fuel  : Natural)
   is
   begin
      if Fuel > K then
         Lemma_Follow_After_Null (Links, Head, K, Fuel - 1);
         Lemma_Terminated_Prefix (Links, Head, Id, K, Fuel - 1);
      end if;
   end Lemma_Terminated_Prefix;

   procedure Lemma_Present_Implies_Full
     (Links : Task_Links;
      Head  : Optional_Task_Id;
      Fuel  : Natural)
   is
   begin
      if Fuel > 1 then
         Lemma_Follow_Compose (Links, Head, Fuel - 2, 1);
         Lemma_Present_Implies_Full (Links, Head, Fuel - 1);
      end if;
   end Lemma_Present_Implies_Full;

   procedure Lemma_Short_Chain_Null
     (Links : Task_Links;
      Head  : Optional_Task_Id)
   is
   begin
      if Follow (Links, Head, Max_Tasks - 1) /= No_Task then
         Lemma_Present_Implies_Full (Links, Head, Max_Tasks);
      end if;
   end Lemma_Short_Chain_Null;

   procedure Lemma_Two_Node_Chain
     (Links  : Task_Links;
      First  : Task_Id;
      Second : Task_Id)
   is
   begin
      Lemma_Follow_Null (Links, Max_Tasks - 2);
      Lemma_Follow_Compose
        (Links, To_Optional (First), 2, Max_Tasks - 2);
      Lemma_Terminated_Prefix
        (Links, To_Optional (First), First, 2, Max_Tasks);
      Lemma_Terminated_Prefix
        (Links, To_Optional (First), Second, 2, Max_Tasks);
      for Other in Task_Id loop
         Lemma_Terminated_Prefix
           (Links, To_Optional (First), Other, 2, Max_Tasks);
         pragma Loop_Invariant
           (for all T in Task_Id'First .. Other =>
              (if T /= First and then T /= Second then
                 Chain_Occurrences (Links, To_Optional (First), T) = 0));
      end loop;
   end Lemma_Two_Node_Chain;

   procedure Lemma_Append_Walk
     (Before, After : Task_Links;
      Start         : Optional_Task_Id;
      Tail          : Task_Id;
      Id            : Task_Id)
   is
   begin
      if Start = To_Optional (Tail) then
         Lemma_Two_Node_Chain (After, Tail, Id);
         Lemma_Singleton_Chain (Before, Tail);
      else
         Lemma_Dequeue_Length (Before, Start);
         Lemma_Dequeue_Occurrences (Before, Start, Tail);
         Lemma_Dequeue_Occurrences (Before, Start, Id);
         Lemma_Append_Walk
           (Before, After, Before (To_Task_Id (Start)), Tail, Id);
         Lemma_Follow_Shift
           (After, Start,
            Chain_Length (Before, Before (To_Task_Id (Start))));
         Lemma_Short_Chain_Null (After, After (To_Task_Id (Start)));
         Lemma_Follow_Shift (After, Start, Max_Tasks - 1);
         Lemma_Length_Tail_Prefix (After, Start, Max_Tasks);
         Lemma_Occurrence_Tail_Prefix (After, Start, Id, Max_Tasks);
         Lemma_Occurrence_Tail_Prefix (After, Start, Tail, Max_Tasks);
      end if;
      pragma Assert (Chain_Terminates (After, Start));
      for Other in Task_Id loop
         if Other /= Id then
            Lemma_Dequeue_Occurrences (Before, Start, Other);
            Lemma_Dequeue_Occurrences (After, Start, Other);
         end if;
         pragma Loop_Invariant
           (for all T in Task_Id'First .. Other =>
              (if T /= Id then
                 Chain_Occurrences (After, Start, T) =
                   Chain_Occurrences (Before, Start, T)));
      end loop;
   end Lemma_Append_Walk;

   procedure Lemma_Append_At_Tail
     (Before, After : Task_Links;
      Head          : Optional_Task_Id;
      Tail          : Task_Id;
      Id            : Task_Id)
   is
   begin
      Lemma_Append_Walk (Before, After, Head, Tail, Id);
   end Lemma_Append_At_Tail;

   procedure Lemma_Follow_Priority
     (S : Scheduler; Head : Optional_Task_Id; P : Priority; Steps : Natural)
   is
   begin
      if Steps > 0 and then Head /= No_Task then
         Lemma_Follow_Priority
           (S, S.Next (To_Task_Id (Head)), P, Steps - 1);
      end if;
   end Lemma_Follow_Priority;

   procedure Lemma_Occurrence_Validity
     (S : Scheduler; P : Priority; T : Task_Id; Fuel : Natural)
   is
   begin
      if Fuel > 0 then
         Lemma_Occurrence_Validity (S, P, T, Fuel - 1);
         Lemma_Follow_Priority (S, S.Heads (P), P, Fuel - 1);
      end if;
   end Lemma_Occurrence_Validity;

   procedure Lemma_Local_Reachability (S : Scheduler) is
   begin
      for P in Priority loop
         for T in Task_Id loop
            Lemma_Occurrence_Validity (S, P, T, Max_Tasks);
            pragma Loop_Invariant
              (for all U in Task_Id'First .. T =>
                 (if Chain_Occurrences (S.Next, S.Heads (P), U) > 0 then
                    S.States (U) = Ready and then S.Priorities (U) = P));
         end loop;
         pragma Loop_Invariant
           (for all Q in Priority'First .. P =>
              (for all T in Task_Id =>
                 (if Chain_Occurrences (S.Next, S.Heads (Q), T) > 0 then
                    S.States (T) = Ready and then S.Priorities (T) = Q)));
      end loop;
   end Lemma_Local_Reachability;

   procedure Lemma_Distinct_Priorities_Disjoint
     (S : Scheduler; P, Q : Priority; T : Task_Id)
   is
   begin
      Lemma_Occurrence_Validity (S, P, T, Max_Tasks);
      Lemma_Occurrence_Validity (S, Q, T, Max_Tasks);
   end Lemma_Distinct_Priorities_Disjoint;

   function Count_Ready_States
     (States : Task_State_Map) return Ready_Count_Type
   is
      Count : Ready_Count_Type := 0;
   begin
      --  Fixed sixteen-entry scalar scan; ghost only, no queue traversal.
      for T in Task_Id loop
         pragma Loop_Invariant
           (Count = Ready_Prefix (States, Natural (T) - 1));
         if States (T) = Ready then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Count_Ready_States;

   procedure Lemma_State_Update
     (Before, After : Task_State_Map; Id : Task_Id; Last : Natural)
   is
   begin
      if Last > 0 then
         Lemma_State_Update (Before, After, Id, Last - 1);
      end if;
   end Lemma_State_Update;

   procedure Enqueue
     (S  : in out Scheduler;
      P  : Priority;
      Id : Task_Id)
   is
      Old_Tail : Optional_Task_Id;
   begin
      if S.Heads (P) = No_Task then
         S.Heads (P) := To_Optional (Id);
         S.Tails (P) := To_Optional (Id);
         S.Next (Id) := No_Task;
         S.Nonempty (P) := True;
      else
         Old_Tail := S.Tails (P);
         S.Next (To_Task_Id (Old_Tail)) := To_Optional (Id);
         S.Tails (P) := To_Optional (Id);
         S.Next (Id) := No_Task;
         S.Nonempty (P) := True;
      end if;
   end Enqueue;

   procedure Dequeue
     (S  : in out Scheduler;
      P  : Priority;
      Id : out Task_Id)
   is
      Old_Head : constant Optional_Task_Id := S.Heads (P);
      New_Head : Optional_Task_Id;
   begin
      Id := To_Task_Id (Old_Head);
      New_Head := S.Next (Id);
      S.Heads (P) := New_Head;
      S.Next (Id) := No_Task;

      if New_Head = No_Task then
         S.Tails (P) := No_Task;
         S.Nonempty (P) := False;
      else
         S.Nonempty (P) := True;
      end if;
   end Dequeue;

   procedure Find_Highest_Ready
     (S        : Scheduler;
      Found    : out Boolean;
      Selected : out Priority)
   is
   begin
      Found := False;
      Selected := Priority'First;

      for P in reverse Priority loop
         pragma Loop_Invariant
           (for all Q in Priority =>
              (if Q > P then not S.Nonempty (Q)));
         pragma Loop_Invariant (not Found);

         if S.Nonempty (P) then
            Found := True;
            Selected := P;
            return;
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

   procedure Initialize
     (S          : out Scheduler;
      Priorities : Task_Priorities)
   is
   begin
      S.Initialized := True;
      S.Current := No_Task;
      S.Priorities := Priorities;
      S.States := (others => Dormant);
      S.Heads := (others => No_Task);
      S.Tails := (others => No_Task);
      S.Next := (others => No_Task);
      S.Nonempty := (others => False);
      S.Ready_Count := 0;
   end Initialize;

   procedure Make_Ready (S : in out Scheduler; Id : Task_Id) is
      P : constant Priority := S.Priorities (Id);
   begin
      pragma Assert
        (for all Q in Priority =>
           S.Heads (Q) /= To_Optional (Id)
           and then S.Tails (Q) /= To_Optional (Id));

      pragma Assert
        (for all T in Task_Id => S.Next (T) /= To_Optional (Id));
      pragma Assert (Ready_Count_State_Valid (S));
      declare
         Before : constant Task_State_Map := S.States with Ghost;
      begin
         pragma Assert (S.Ready_Count = Count_Ready_States (Before));
         S.States (Id) := Ready;
         Lemma_State_Update (Before, S.States, Id, Max_Tasks);
         pragma Assert
           (Integer (Count_Ready_States (S.States)) =
              Integer (Count_Ready_States (Before))
              + (if S.States (Id) = Ready then 1 else 0)
              - (if Before (Id) = Ready then 1 else 0));
         pragma Assert
           (Count_Ready_States (S.States) = S.Ready_Count + 1);
      end;
      Enqueue (S, P, Id);
      S.Ready_Count := S.Ready_Count + 1;
   end Make_Ready;

   procedure Block (S : in out Scheduler; Id : Task_Id) is
   begin
      pragma Assert (Ready_Count_State_Valid (S));
      declare
         Before : constant Task_State_Map := S.States with Ghost;
      begin
         S.States (Id) := Blocked;
         Lemma_State_Update (Before, S.States, Id, Max_Tasks);
         pragma Assert
           (Integer (Count_Ready_States (S.States)) =
              Integer (Count_Ready_States (Before))
              + (if S.States (Id) = Ready then 1 else 0)
              - (if Before (Id) = Ready then 1 else 0));
      end;
      S.Current := No_Task;
   end Block;

   procedure Select_Next (S : in out Scheduler) is
      Found    : Boolean;
      Selected : Priority;
      Id       : Task_Id;
   begin
      if not Any_Ready (S) then
         return;
      end if;

      Find_Highest_Ready (S, Found, Selected);
      pragma Assert (Found);
      pragma Assert (S.Nonempty (Selected));
      pragma Assert (S.Heads (Selected) /= No_Task);

      Dequeue (S, Selected, Id);

      pragma Assert (S.Next (Id) = No_Task);
      pragma Assert (S.Priorities (Id) = Selected);

      pragma Assert (Ready_Count_State_Valid (S));
      declare
         Before : constant Task_State_Map := S.States with Ghost;
      begin
         pragma Assert (S.Ready_Count = Count_Ready_States (Before));
         S.States (Id) := Running;
         Lemma_State_Update (Before, S.States, Id, Max_Tasks);
         pragma Assert
           (Integer (Count_Ready_States (S.States)) =
              Integer (Count_Ready_States (Before))
              + (if S.States (Id) = Ready then 1 else 0)
              - (if Before (Id) = Ready then 1 else 0));
         pragma Assert
           (Count_Ready_States (S.States) = S.Ready_Count - 1);
      end;
      S.Current := To_Optional (Id);

      S.Ready_Count := S.Ready_Count - 1;
   end Select_Next;

   procedure Yield (S : in out Scheduler) is
      Id : constant Task_Id := To_Task_Id (S.Current);
      P  : constant Priority := S.Priorities (Id);
   begin
      pragma Assert
        (for all Q in Priority =>
           S.Heads (Q) /= To_Optional (Id)
           and then S.Tails (Q) /= To_Optional (Id));

      S.Current := No_Task;
      pragma Assert
        (for all T in Task_Id => S.Next (T) /= To_Optional (Id));
      pragma Assert (Ready_Count_State_Valid (S));
      declare
         Before : constant Task_State_Map := S.States with Ghost;
      begin
         pragma Assert (S.Ready_Count = Count_Ready_States (Before));
         S.States (Id) := Ready;
         Lemma_State_Update (Before, S.States, Id, Max_Tasks);
         pragma Assert
           (Integer (Count_Ready_States (S.States)) =
              Integer (Count_Ready_States (Before))
              + (if S.States (Id) = Ready then 1 else 0)
              - (if Before (Id) = Ready then 1 else 0));
         pragma Assert
           (Count_Ready_States (S.States) = S.Ready_Count + 1);
      end;
      Enqueue (S, P, Id);
      S.Ready_Count := S.Ready_Count + 1;

      pragma Assert (S.Current = No_Task);
      pragma Assert (S.States (Id) = Ready);
      pragma Assert (S.Nonempty (P));
      pragma Assert (Indexed_Scheduler_Valid (S));

      Select_Next (S);
   end Yield;

   procedure Schedule (S : in out Scheduler) is
      Id      : Task_Id;
      Prio    : Priority;
      Found   : Boolean;
      Highest : Priority;
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
         pragma Assert (No_Ready_Above (S, Prio));
         pragma Assert (S.Current = To_Optional (Id));
         return;
      end if;

      pragma Assert (Found);
      pragma Assert (Highest > Prio);
      pragma Assert (S.Nonempty (Highest));
      pragma Assert (not No_Ready_Above (S, Prio));
      pragma Assert
        (for all Q in Priority =>
           S.Heads (Q) /= To_Optional (Id)
           and then S.Tails (Q) /= To_Optional (Id));

      S.Current := No_Task;
      pragma Assert
        (for all T in Task_Id => S.Next (T) /= To_Optional (Id));
      pragma Assert (Ready_Count_State_Valid (S));
      declare
         Before : constant Task_State_Map := S.States with Ghost;
      begin
         pragma Assert (S.Ready_Count = Count_Ready_States (Before));
         S.States (Id) := Ready;
         Lemma_State_Update (Before, S.States, Id, Max_Tasks);
         pragma Assert
           (Integer (Count_Ready_States (S.States)) =
              Integer (Count_Ready_States (Before))
              + (if S.States (Id) = Ready then 1 else 0)
              - (if Before (Id) = Ready then 1 else 0));
         pragma Assert
           (Count_Ready_States (S.States) = S.Ready_Count + 1);
      end;
      Enqueue (S, Prio, Id);
      S.Ready_Count := S.Ready_Count + 1;

      pragma Assert (S.Current = No_Task);
      pragma Assert (S.States (Id) = Ready);
      pragma Assert (Indexed_Scheduler_Valid (S));

      Select_Next (S);
   end Schedule;

end RTOS.Indexed_Scheduler;
