defmodule ChatbotWeb.Live.Chat.TaskRegistry do
  @moduledoc """
  Manages per-user concurrent streaming task limits using ETS.

  Provides rate limiting for concurrent streaming operations to prevent
  resource exhaustion. Each user is limited to a configurable number
  of concurrent streaming tasks.

  ## Usage

      # Check if user can start a new task
      if TaskRegistry.can_start_task?(user_id) do
        TaskRegistry.register_task(user_id, task_pid)
        # ... start the task
      end

      # When task completes
      TaskRegistry.unregister_task(user_id, task_pid)

  """

  @max_concurrent_tasks 3
  @task_registry_table :streaming_tasks

  @doc """
  Ensures the task registry ETS table exists.
  Called lazily when needed.
  """
  @spec ensure_registry() :: :ok
  def ensure_registry do
    case :ets.whereis(@task_registry_table) do
      :undefined ->
        :ets.new(@task_registry_table, [:set, :public, :named_table])
        :ok

      _ref ->
        :ok
    end
  end

  @doc """
  Checks if the user can start a new streaming task (within concurrent limit).
  """
  @spec can_start_task?(binary()) :: boolean()
  def can_start_task?(user_id) do
    ensure_registry()
    count = get_task_count(user_id)
    count < @max_concurrent_tasks
  end

  @doc """
  Registers a new streaming task for a user.
  """
  @spec register_task(binary(), pid()) :: :ok
  def register_task(user_id, task_pid) do
    ensure_registry()
    key = {user_id, task_pid}
    :ets.insert(@task_registry_table, {key, System.monotonic_time(:millisecond)})
    :ok
  end

  @doc """
  Unregisters a streaming task when it completes.
  """
  @spec unregister_task(binary(), pid()) :: :ok
  def unregister_task(user_id, task_pid) do
    ensure_registry()
    key = {user_id, task_pid}
    :ets.delete(@task_registry_table, key)
    :ok
  end

  @doc """
  Gets the count of active tasks for a user.
  """
  @spec get_task_count(binary()) :: non_neg_integer()
  def get_task_count(user_id) do
    ensure_registry()

    counter = fn
      {{uid, _pid}, _time}, acc when uid == user_id -> acc + 1
      _entry, acc -> acc
    end

    :ets.foldl(counter, 0, @task_registry_table)
  end

  @doc """
  Returns the maximum number of concurrent tasks allowed per user.
  """
  @spec max_concurrent_tasks() :: pos_integer()
  def max_concurrent_tasks, do: @max_concurrent_tasks
end
