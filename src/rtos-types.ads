--  Common, statically bounded types for both scheduler representations.

package RTOS.Types
  with SPARK_Mode => On,
       Pure
is

   --  Static population of tasks. Identities are never allocated at
   --  run time; every Task_Id exists for the life of a scheduler.
   Max_Tasks : constant := 16;

   --  Valid task identities. There is no Task_Id for "no task".
   type Task_Id is range 1 .. Max_Tasks;

   --  Optional task identity used for empty current-task slots and
   --  indexed list links. No_Task is a named sentinel, not a Task_Id.
   type Optional_Task_Id is range 0 .. Max_Tasks;
   No_Task : constant Optional_Task_Id := 0;

   function Has_Task (Id : Optional_Task_Id) return Boolean
   is (Id /= No_Task);

   function To_Optional (Id : Task_Id) return Optional_Task_Id
   is (Optional_Task_Id (Id));

   function To_Task_Id (Id : Optional_Task_Id) return Task_Id
   is (Task_Id (Id))
   with
     Pre => Has_Task (Id);

   --  Eight fixed-priority levels. Larger values are more urgent, so
   --  Priority'Last is the highest priority. The zero-based range is
   --  intended to remain bitmap-friendly for later selection work.
   Priority_Count : constant := 8;
   type Priority is range 0 .. Priority_Count - 1;

   type Task_State is (Dormant, Ready, Running, Blocked);

   type Task_Priorities is array (Task_Id) of Priority;
   type Task_State_Map is array (Task_Id) of Task_State;

end RTOS.Types;
