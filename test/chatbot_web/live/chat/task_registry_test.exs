defmodule ChatbotWeb.Live.Chat.TaskRegistryTest do
  use ExUnit.Case, async: false

  alias ChatbotWeb.Live.Chat.TaskRegistry

  setup do
    # Ensure registry exists and clear entries before each test
    # Use delete_all_objects instead of deleting the table to avoid
    # race conditions with other tests
    TaskRegistry.ensure_registry()

    try do
      :ets.delete_all_objects(:streaming_tasks)
    rescue
      ArgumentError -> :ok
    end

    try do
      :ets.delete_all_objects(:streaming_task_counters)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  describe "try_register_task/2" do
    test "successfully registers a task within limit" do
      user_id = "user-1"
      task_pid = self()

      assert :ok = TaskRegistry.try_register_task(user_id, task_pid)
      assert TaskRegistry.get_task_count(user_id) == 1
    end

    test "allows up to max_concurrent_tasks" do
      user_id = "user-2"
      max = TaskRegistry.max_concurrent_tasks()

      pids =
        for _i <- 1..max do
          pid = spawn(fn -> :timer.sleep(:infinity) end)
          assert :ok = TaskRegistry.try_register_task(user_id, pid)
          pid
        end

      assert TaskRegistry.get_task_count(user_id) == max

      # Cleanup
      Enum.each(pids, &Process.exit(&1, :kill))
    end

    test "rejects task when at limit" do
      user_id = "user-3"
      max = TaskRegistry.max_concurrent_tasks()

      # Register max tasks
      pids =
        for _i <- 1..max do
          pid = spawn(fn -> :timer.sleep(:infinity) end)
          assert :ok = TaskRegistry.try_register_task(user_id, pid)
          pid
        end

      # Try to register one more
      extra_pid = spawn(fn -> :timer.sleep(:infinity) end)
      assert {:error, :limit_exceeded} = TaskRegistry.try_register_task(user_id, extra_pid)

      # Counter should not have increased
      assert TaskRegistry.get_task_count(user_id) == max

      # Cleanup
      Process.exit(extra_pid, :kill)
      Enum.each(pids, &Process.exit(&1, :kill))
    end

    test "different users have independent limits" do
      user_a = "user-a"
      user_b = "user-b"
      max = TaskRegistry.max_concurrent_tasks()

      # Fill up user A's slots
      pids_a =
        for _i <- 1..max do
          pid = spawn(fn -> :timer.sleep(:infinity) end)
          assert :ok = TaskRegistry.try_register_task(user_a, pid)
          pid
        end

      # User B should still be able to register
      pid_b = spawn(fn -> :timer.sleep(:infinity) end)
      assert :ok = TaskRegistry.try_register_task(user_b, pid_b)

      assert TaskRegistry.get_task_count(user_a) == max
      assert TaskRegistry.get_task_count(user_b) == 1

      # Cleanup
      Enum.each(pids_a, &Process.exit(&1, :kill))
      Process.exit(pid_b, :kill)
    end
  end

  describe "unregister_task/2" do
    test "decrements counter when unregistering" do
      user_id = "user-4"
      pid1 = spawn(fn -> :timer.sleep(:infinity) end)
      pid2 = spawn(fn -> :timer.sleep(:infinity) end)

      :ok = TaskRegistry.try_register_task(user_id, pid1)
      :ok = TaskRegistry.try_register_task(user_id, pid2)
      assert TaskRegistry.get_task_count(user_id) == 2

      :ok = TaskRegistry.unregister_task(user_id, pid1)
      assert TaskRegistry.get_task_count(user_id) == 1

      :ok = TaskRegistry.unregister_task(user_id, pid2)
      assert TaskRegistry.get_task_count(user_id) == 0

      # Cleanup
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "does not decrement below zero" do
      user_id = "user-5"
      fake_pid = spawn(fn -> :ok end)

      # Unregister a task that was never registered
      :ok = TaskRegistry.unregister_task(user_id, fake_pid)

      assert TaskRegistry.get_task_count(user_id) == 0
    end

    test "idempotent - unregistering twice is safe" do
      user_id = "user-6"
      pid = spawn(fn -> :timer.sleep(:infinity) end)

      :ok = TaskRegistry.try_register_task(user_id, pid)
      assert TaskRegistry.get_task_count(user_id) == 1

      :ok = TaskRegistry.unregister_task(user_id, pid)
      assert TaskRegistry.get_task_count(user_id) == 0

      # Unregister again - should be safe
      :ok = TaskRegistry.unregister_task(user_id, pid)
      assert TaskRegistry.get_task_count(user_id) == 0

      Process.exit(pid, :kill)
    end
  end

  describe "race condition prevention" do
    test "concurrent registrations respect limit" do
      user_id = "user-race"
      max = TaskRegistry.max_concurrent_tasks()
      num_concurrent = max * 3

      # Ensure registry is initialized before spawning tasks
      TaskRegistry.ensure_registry()

      # Spawn many processes trying to register concurrently
      tasks =
        for _i <- 1..num_concurrent do
          Task.async(fn ->
            pid = spawn(fn -> :timer.sleep(:infinity) end)
            result = TaskRegistry.try_register_task(user_id, pid)
            {result, pid}
          end)
        end

      # Wait for all to complete
      results = Task.await_many(tasks, 5000)

      successful = Enum.count(results, fn {result, _pid} -> result == :ok end)
      rejected = Enum.count(results, fn {result, _pid} -> result == {:error, :limit_exceeded} end)

      # Exactly max should succeed
      assert successful == max
      assert rejected == num_concurrent - max

      # Final count should be exactly max
      assert TaskRegistry.get_task_count(user_id) == max

      # Cleanup
      Enum.each(results, fn {_result, pid} -> Process.exit(pid, :kill) end)
    end
  end

  describe "cleanup_stale_tasks/1" do
    test "removes dead processes and resets counter" do
      user_id = "user-cleanup"

      # Register some tasks
      pid1 = spawn(fn -> :timer.sleep(:infinity) end)
      pid2 = spawn(fn -> :timer.sleep(:infinity) end)

      :ok = TaskRegistry.try_register_task(user_id, pid1)
      :ok = TaskRegistry.try_register_task(user_id, pid2)

      assert TaskRegistry.get_task_count(user_id) == 2

      # Kill one process
      Process.exit(pid1, :kill)
      :timer.sleep(10)

      # Counter still shows 2
      assert TaskRegistry.get_task_count(user_id) == 2

      # Cleanup stale tasks
      :ok = TaskRegistry.cleanup_stale_tasks(user_id)

      # Now counter should be 1
      assert TaskRegistry.get_task_count(user_id) == 1

      # Cleanup
      Process.exit(pid2, :kill)
    end
  end

  describe "can_start_task?/1" do
    test "returns true when under limit" do
      user_id = "user-can-start"
      assert TaskRegistry.can_start_task?(user_id) == true
    end

    test "returns false when at limit" do
      user_id = "user-cannot-start"
      max = TaskRegistry.max_concurrent_tasks()

      pids =
        for _i <- 1..max do
          pid = spawn(fn -> :timer.sleep(:infinity) end)
          :ok = TaskRegistry.try_register_task(user_id, pid)
          pid
        end

      assert TaskRegistry.can_start_task?(user_id) == false

      # Cleanup
      Enum.each(pids, &Process.exit(&1, :kill))
    end
  end
end
