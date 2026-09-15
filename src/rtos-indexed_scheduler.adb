package body RTOS.Indexed_Scheduler
  with SPARK_Mode => On
is

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
