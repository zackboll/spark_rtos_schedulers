with RTOS.Types;

--  Indexed fixed-priority scheduler.
--
--  Ready membership will eventually be represented with Task_Id links
--  rather than Ada access types:
--
--    Head (P) -> Task_Id -> Task_Id -> Task_Id
--                                      ^
--                                      |
--                                    Tail (P)
--
--  Head, Tail, and Next store Optional_Task_Id values. This preserves
--  linked-queue behavior while avoiding writable pointer aliasing, and
--  is intended to allow O(1) enqueue, dequeue, and same-priority yield.
--
--  This package establishes the architecture only. Ready-queue
--  algorithms are not implemented yet.

package RTOS.Indexed_Scheduler
  with SPARK_Mode => On
is

   use RTOS.Types;

   type Scheduler is limited private
     with Default_Initial_Condition =>
       not Is_Initialized (Scheduler);

   function Is_Initialized (S : Scheduler) return Boolean
     with Ghost;

   function Current_Task (S : Scheduler) return Optional_Task_Id
   with
     Pre => Is_Initialized (S);

   procedure Initialize
     (S          : out Scheduler;
      Priorities : Task_Priorities)
   with
     Post => Is_Initialized (S)
     and then Current_Task (S) = No_Task;

   procedure Make_Ready (S : in out Scheduler; Id : Task_Id)
   with
     Pre  => Is_Initialized (S),
     Post => Is_Initialized (S);

   procedure Block (S : in out Scheduler; Id : Task_Id)
   with
     Pre  => Is_Initialized (S),
     Post => Is_Initialized (S);

   procedure Yield (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S),
     Post => Is_Initialized (S);

   procedure Select_Next (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S),
     Post => Is_Initialized (S);

   procedure Schedule (S : in out Scheduler)
   with
     Pre  => Is_Initialized (S),
     Post => Is_Initialized (S);

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
   end record;

   function Is_Initialized (S : Scheduler) return Boolean
   is (S.Initialized);

   function Current_Task (S : Scheduler) return Optional_Task_Id
   is (S.Current);

end RTOS.Indexed_Scheduler;
