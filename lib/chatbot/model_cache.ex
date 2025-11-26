defmodule Chatbot.ModelCache do
  @moduledoc """
  ETS-based cache for LM Studio model list.

  Caches the list of available models to avoid repeated API calls to LM Studio.
  The cache has a configurable TTL (time-to-live) after which the models are refreshed.
  """
  use GenServer

  require Logger

  @table_name :model_cache
  @default_ttl_ms 60_000

  # Client API

  @doc """
  Starts the ModelCache GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the cached model list, fetching from LM Studio if needed.
  Returns {:ok, models} or {:error, reason}.

  Uses GenServer call to serialize cache misses and prevent thundering herd.
  """
  @spec get_models() :: {:ok, [map()]} | {:error, String.t()}
  def get_models do
    case lookup_models() do
      {:ok, models} ->
        {:ok, models}

      :miss ->
        # Cache miss - use GenServer call to serialize fetches
        GenServer.call(__MODULE__, :fetch_models)
    end
  end

  @doc """
  Forces a refresh of the model cache.
  """
  @spec refresh() :: :ok
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Clears the model cache.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call(:fetch_models, _from, state) do
    # Double-check pattern - cache may have been populated by another process
    case lookup_models() do
      {:ok, models} ->
        {:reply, {:ok, models}, state}

      :miss ->
        result = lm_studio_client().list_models()

        case result do
          {:ok, models} -> cache_models(models)
          _error -> :ok
        end

        {:reply, result, state}
    end
  end

  @impl GenServer
  def handle_cast(:refresh, state) do
    case lm_studio_client().list_models() do
      {:ok, models} ->
        cache_models(models)

      {:error, reason} ->
        Logger.warning("Failed to refresh model cache: #{reason}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(@table_name)
    {:noreply, state}
  end

  # Private functions

  defp lm_studio_client do
    Application.get_env(:chatbot, :lm_studio_client, Chatbot.LMStudio)
  end

  defp lookup_models do
    ttl = Application.get_env(:chatbot, :model_cache, [])[:ttl_ms] || @default_ttl_ms

    case :ets.lookup(@table_name, :models) do
      [{:models, models, cached_at}] ->
        if System.monotonic_time(:millisecond) - cached_at < ttl do
          {:ok, models}
        else
          :miss
        end

      [] ->
        :miss
    end
  end

  defp cache_models(models) do
    :ets.insert(@table_name, {:models, models, System.monotonic_time(:millisecond)})
  end
end
