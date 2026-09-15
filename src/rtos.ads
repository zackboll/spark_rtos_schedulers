--  Parent namespace for the educational SPARK RTOS scheduler models.
--
--  This crate compares two representations of the same fixed-priority
--  preemptive scheduler:
--
--    * RTOS.Pointer_Scheduler, which will use owned singly linked lists
--    * RTOS.Indexed_Scheduler, which will use Task_Id links rather than
--      Ada access types
--
--  Shared identities, priorities, and task states live in RTOS.Types.
--  Neither scheduler performs machine context switching, interrupt
--  handling, or dynamic task creation.

package RTOS
  with SPARK_Mode => On,
       Pure
is

end RTOS;
