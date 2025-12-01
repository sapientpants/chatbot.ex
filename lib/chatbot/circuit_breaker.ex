defmodule Chatbot.CircuitBreaker do
  @moduledoc """
  Shared circuit breaker functionality using the Fuse library.

  Provides protection against cascading failures when external services
  are unavailable. When a service fails repeatedly, the circuit "opens"
  and subsequent calls fail fast without attempting the operation.

  ## Configuration

  Each fuse can be configured with:
  - `max_failures` - Number of failures before circuit opens (default: 5)
  - `window_ms` - Time window for counting failures (default: 60,000ms)
  - `reset_ms` - Time before attempting to close circuit (default: 30,000ms)

  ## Usage

      # Install a fuse (typically at application startup)
      CircuitBreaker.install(:my_service_fuse)

      # Execute a function with circuit breaker protection
      CircuitBreaker.with_fuse(:my_service_fuse, fn ->
        MyService.call()
      end)

  """

  require Logger

  @default_max_failures 5
  @default_window_ms 60_000
  @default_reset_ms 30_000

  @type fuse_name :: atom()
  @type fuse_options :: [
          max_failures: pos_integer(),
          window_ms: pos_integer(),
          reset_ms: pos_integer()
        ]

  @doc """
  Installs a circuit breaker fuse with the given name and options.

  ## Options

  - `:max_failures` - Number of failures before circuit opens (default: 5)
  - `:window_ms` - Time window in milliseconds for counting failures (default: 60,000)
  - `:reset_ms` - Time in milliseconds before attempting reset (default: 30,000)

  ## Examples

      CircuitBreaker.install(:ollama_fuse)
      CircuitBreaker.install(:lmstudio_fuse, max_failures: 3, reset_ms: 15_000)

  """
  @spec install(fuse_name(), fuse_options()) :: :ok
  def install(fuse_name, opts \\ []) do
    max_failures = Keyword.get(opts, :max_failures, @default_max_failures)
    window_ms = Keyword.get(opts, :window_ms, @default_window_ms)
    reset_ms = Keyword.get(opts, :reset_ms, @default_reset_ms)

    fuse_opts = {{:standard, max_failures, window_ms}, {:reset, reset_ms}}
    :fuse.install(fuse_name, fuse_opts)
    :ok
  end

  @doc """
  Ensures a fuse is installed, installing it with defaults if not found.

  Returns:
  - `:ok` - Fuse is ready to use
  - `:blown` - Circuit is currently open

  ## Examples

      case CircuitBreaker.ensure_installed(:my_fuse) do
        :ok -> # proceed with operation
        :blown -> {:error, "Service unavailable"}
      end

  """
  @spec ensure_installed(fuse_name(), fuse_options()) :: :ok | :blown
  def ensure_installed(fuse_name, opts \\ []) do
    case :fuse.ask(fuse_name, :sync) do
      :ok ->
        :ok

      :blown ->
        :blown

      {:error, :not_found} ->
        install(fuse_name, opts)
        :ok
    end
  end

  @doc """
  Executes a function with circuit breaker protection.

  If the circuit is open (blown), returns an error immediately without
  executing the function. If the function returns an error tuple,
  records a failure (melts the fuse).

  ## Parameters

  - `fuse_name` - The name of the fuse to use
  - `fun` - Zero-arity function to execute
  - `opts` - Options for fuse installation if not already installed

  ## Returns

  - The result of `fun.()` if circuit is closed
  - `{:error, :circuit_open}` if circuit is open
  - `{:error, reason}` if function fails (also records failure)

  ## Examples

      CircuitBreaker.with_fuse(:ollama_fuse, fn ->
        Req.post(url, json: body)
      end)

  """
  @spec with_fuse(fuse_name(), (-> result), fuse_options()) :: result | {:error, :circuit_open}
        when result: any()
  def with_fuse(fuse_name, fun, opts \\ []) do
    case ensure_installed(fuse_name, opts) do
      :blown ->
        {:error, :circuit_open}

      :ok ->
        execute_with_fuse(fuse_name, fun)
    end
  end

  @doc """
  Checks if a circuit breaker is currently open (blown).

  ## Examples

      if CircuitBreaker.blown?(:ollama_fuse) do
        {:error, "Service temporarily unavailable"}
      end

  """
  @spec blown?(fuse_name()) :: boolean()
  def blown?(fuse_name) do
    case :fuse.ask(fuse_name, :sync) do
      :blown -> true
      _other -> false
    end
  end

  @doc """
  Manually records a failure for the given fuse.

  Useful when you need to record failures based on custom logic
  (e.g., specific HTTP status codes).

  ## Examples

      case response.status do
        500 -> CircuitBreaker.melt(:my_fuse)
        _ -> :ok
      end

  """
  @spec melt(fuse_name()) :: :ok
  def melt(fuse_name) do
    :fuse.melt(fuse_name)
    :ok
  end

  @doc """
  Resets a fuse, closing the circuit.

  Typically called after a successful operation to indicate
  the service is healthy again.

  ## Examples

      CircuitBreaker.reset(:my_fuse)

  """
  @spec reset(fuse_name()) :: :ok
  def reset(fuse_name) do
    :fuse.reset(fuse_name)
    :ok
  end

  # Private helpers

  defp execute_with_fuse(fuse_name, fun) do
    result = fun.()

    case result do
      {:error, _reason} ->
        :fuse.melt(fuse_name)
        result

      _success ->
        result
    end
  rescue
    e ->
      :fuse.melt(fuse_name)
      Logger.warning("Circuit breaker #{fuse_name} caught exception: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end
end
