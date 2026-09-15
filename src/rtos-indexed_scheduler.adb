package body RTOS.Indexed_Scheduler
  with SPARK_Mode => On
is

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
   end Initialize;

   procedure Make_Ready (S : in out Scheduler; Id : Task_Id) is
   begin
      --  Indexed enqueue is not implemented in this skeleton.
      S.States (Id) := Ready;
   end Make_Ready;

   procedure Block (S : in out Scheduler; Id : Task_Id) is
   begin
      --  Indexed dequeue is not implemented in this skeleton.
      S.States (Id) := Blocked;
      if S.Current = To_Optional (Id) then
         S.Current := No_Task;
      end if;
   end Block;

   procedure Yield (S : in out Scheduler) is
   begin
      --  Same-priority requeue is not implemented in this skeleton.
      if Has_Task (S.Current) then
         S.States (To_Task_Id (S.Current)) := Ready;
         S.Current := No_Task;
      end if;
   end Yield;

   procedure Select_Next (S : in out Scheduler) is
   begin
      --  Highest-priority selection is not implemented. The skeleton
      --  ready lists are empty, so no task is selected.
      S.Current := No_Task;
   end Select_Next;

   procedure Schedule (S : in out Scheduler) is
   begin
      Select_Next (S);
   end Schedule;

end RTOS.Indexed_Scheduler;
