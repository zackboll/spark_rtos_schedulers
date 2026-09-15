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
      --  Preserve the representation until indexed enqueue is implemented.
      null;
   end Make_Ready;

   procedure Block (S : in out Scheduler; Id : Task_Id) is
   begin
      --  Preserve the representation until indexed dequeue is implemented.
      null;
   end Block;

   procedure Yield (S : in out Scheduler) is
   begin
      --  Preserve the representation until same-priority requeue is wired.
      null;
   end Yield;

   procedure Select_Next (S : in out Scheduler) is
   begin
      --  Preserve the representation until priority selection is wired.
      null;
   end Select_Next;

   procedure Schedule (S : in out Scheduler) is
   begin
      --  Temporary scaffolding: Select_Next also preserves all state.
      Select_Next (S);
   end Schedule;

end RTOS.Indexed_Scheduler;
