defmodule ChatbotWeb.Live.Chat.TaskRegistry do
  @moduledoc """
  Manages per-user concurrent streaming task limits using ETS.

  Provides rate limiting for concurrent streaming operations to prevent
  resource exhaustion. Each user is limited to a configurable number
  of concurrent streaming tasks.

  ## Usage

      # Atomically check and register a task (preferred - avoids race conditions)
      case TaskRegistry.try_register_task(user_id, task_pid) do
        :ok -> # ... start the task
        {:error, :limit_exceeded} -> # ... reject request
      end

      # When task completes
      TaskRegistry.unregister_task(user_id, task_pid)

  ## Race Condition Prevention

  The `try_register_task/2` function uses atomic ETS counter operations to
  prevent race conditions between checking the limit and registering.

  """

  @max_concurrent_tasks 3
  @task_registry_table :streaming_tasks
  @counter_table :streaming_task_counters

  @doc """
  Ensures the task registry ETS tables exist.
  Called lazily when needed.
  """
  @spec ensure_registry() :: :ok
  def ensure_registry do
    ensure_table(@task_registry_table, :set)
    ensure_table(@counter_table, :set)
  end

  defp ensure_table(name, type) do
    case :ets.whereis(name) do
      :undefined ->
        try do
          :ets.new(name, [type, :public, :named_table])
        rescue
          # Another process created the table between our check and creation
          ArgumentError -> :ok
        end

      _ref ->
        :ok
    end
  end

  @doc """
  Atomically tries to register a task, checking the limit first.
  Returns :ok if registered, {:error, :limit_exceeded} if at limit.

  This function prevents the race condition between checking
  `can_start_task?` and calling `register_task`.
  """
  @spec try_register_task(binary(), pid()) :: :ok | {:error, :limit_exceeded}
  def try_register_task(user_id, task_pid) do
    ensure_registry()

    # Atomically increment counter, defaulting to 1 if not present
    new_count =
      :ets.update_counter(
        @counter_table,
        user_id,
        {2, 1},
        {user_id, 0}
      )

    if new_count <= @max_concurrent_tasks do
      # Within limit - register the task
      key = {user_id, task_pid}
      :ets.insert(@task_registry_table, {key, System.monotonic_time(:millisecond)})
      :ok
    else
      # Over limit - decrement counter back and reject
      :ets.update_counter(@counter_table, user_id, {2, -1})
      {:error, :limit_exceeded}
    end
  end

  @doc """
  Checks if the user can start a new streaming task (within concurrent limit).

  NOTE: For race-condition-free registration, use `try_register_task/2` instead
  of checking `can_start_task?` followed by `register_task`.
  """
  @spec can_start_task?(binary()) :: boolean()
  def can_start_task?(user_id) do
    ensure_registry()
    get_task_count(user_id) < @max_concurrent_tasks
  end

  @doc """
  Registers a new streaming task for a user.

  NOTE: For race-condition-free registration, use `try_register_task/2` instead.
  This function is kept for backward compatibility.
  """
  @spec register_task(binary(), pid()) :: :ok
  def register_task(user_id, task_pid) do
    ensure_registry()
    key = {user_id, task_pid}
    :ets.insert(@task_registry_table, {key, System.monotonic_time(:millisecond)})
    :ets.update_counter(@counter_table, user_id, {2, 1}, {user_id, 0})
    :ok
  end

  @doc """
  Unregisters a streaming task when it completes.
  """
  @spec unregister_task(binary(), pid()) :: :ok
  def unregister_task(user_id, task_pid) do
    ensure_registry()
    key = {user_id, task_pid}

    # Only decrement counter if the task was actually registered
    case :ets.lookup(@task_registry_table, key) do
      [_entry] ->
        :ets.delete(@task_registry_table, key)
        # Atomically decrement, but don't go below 0
        :ets.update_counter(@counter_table, user_id, {2, -1, 0, 0}, {user_id, 0})

      [] ->
        :ok
    end

    :ok
  end

  @doc """
  Gets the count of active tasks for a user.
  Uses the atomic counter for O(1) lookup.
  """
  @spec get_task_count(binary()) :: non_neg_integer()
  def get_task_count(user_id) do
    ensure_registry()

    case :ets.lookup(@counter_table, user_id) do
      [{^user_id, count}] -> max(count, 0)
      [] -> 0
    end
  end

  @doc """
  Returns the maximum number of concurrent tasks allowed per user.
  """
  @spec max_concurrent_tasks() :: pos_integer()
  def max_concurrent_tasks, do: @max_concurrent_tasks

  @doc """
  Cleans up stale tasks for a user. Call this if task processes exit unexpectedly.
  Recalculates the counter from actual registered tasks.
  """
  @spec cleanup_stale_tasks(binary()) :: :ok
  def cleanup_stale_tasks(user_id) do
    ensure_registry()

    # Count actual living tasks
    counter_fn = fn
      {{uid, pid}, _time}, acc when uid == user_id ->
        if Process.alive?(pid), do: acc + 1, else: acc

      _entry, acc ->
        acc
    end

    actual_count = :ets.foldl(counter_fn, 0, @task_registry_table)

    # Remove dead task entries
    cleanup_fn = fn
      {{uid, pid} = key, _time}, acc when uid == user_id ->
        unless Process.alive?(pid), do: :ets.delete(@task_registry_table, key)
        acc

      _entry, acc ->
        acc
    end

    :ets.foldl(cleanup_fn, nil, @task_registry_table)

    # Reset counter to actual count
    :ets.insert(@counter_table, {user_id, actual_count})
    :ok
  end
end
