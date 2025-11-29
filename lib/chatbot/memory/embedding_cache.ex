defmodule Chatbot.Memory.EmbeddingCache do
  @moduledoc """
  ETS-based cache for query embeddings.

  Caches embeddings for search queries to avoid repeated Ollama API calls.
  Uses FIFO (time-based) eviction when max cache size is reached - oldest
  entries by insertion time are evicted first.
  """
  use GenServer

  require Logger

  @table_name :embedding_cache
  @default_ttl_ms 300_000
  @default_max_size 1000

  # Client API

  @doc """
  Starts the EmbeddingCache GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets an embedding from cache or computes it using the provided function.

  ## Examples

      iex> get_or_compute("hello world", fn text -> Ollama.embed(text) end)
      {:ok, [0.1, 0.2, ...]}

  """
  @spec get_or_compute(String.t(), (String.t() -> {:ok, [float()]} | {:error, term()})) ::
          {:ok, [float()]} | {:error, term()}
  def get_or_compute(text, compute_fn) when is_binary(text) and is_function(compute_fn, 1) do
    cache_key = hash_key(text)

    case lookup(cache_key) do
      {:ok, embedding} ->
        {:ok, embedding}

      :miss ->
        GenServer.call(__MODULE__, {:compute_and_cache, cache_key, text, compute_fn}, 60_000)
    end
  end

  @doc """
  Puts an embedding directly into the cache.

  ## Examples

      iex> put("hello world", [0.1, 0.2, ...])
      :ok

  """
  @spec put(String.t(), [float()]) :: :ok
  def put(text, embedding) when is_binary(text) and is_list(embedding) do
    GenServer.cast(__MODULE__, {:put, hash_key(text), embedding})
  end

  @doc """
  Clears all cached embeddings.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  @doc """
  Returns the number of cached embeddings.
  """
  @spec size() :: non_neg_integer()
  def size do
    case :ets.info(@table_name) do
      :undefined -> 0
      info -> Keyword.get(info, :size, 0)
    end
  end

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call({:compute_and_cache, cache_key, text, compute_fn}, _from, state) do
    # Double-check pattern - may have been cached by another process
    case lookup(cache_key) do
      {:ok, embedding} ->
        {:reply, {:ok, embedding}, state}

      :miss ->
        result = compute_fn.(text)

        case result do
          {:ok, embedding} ->
            do_put(cache_key, embedding)
            maybe_evict()
            {:reply, {:ok, embedding}, state}

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl GenServer
  def handle_cast({:put, cache_key, embedding}, state) do
    do_put(cache_key, embedding)
    maybe_evict()
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(@table_name)
    {:noreply, state}
  end

  # Private functions

  defp hash_key(text) do
    :crypto.hash(:sha256, text)
  end

  defp lookup(cache_key) do
    ttl = config()[:ttl_ms] || @default_ttl_ms

    case :ets.lookup(@table_name, cache_key) do
      [{^cache_key, embedding, cached_at}] ->
        if System.monotonic_time(:millisecond) - cached_at < ttl do
          {:ok, embedding}
        else
          # Expired - delete it
          :ets.delete(@table_name, cache_key)
          :miss
        end

      [] ->
        :miss
    end
  end

  defp do_put(cache_key, embedding) do
    :ets.insert(@table_name, {cache_key, embedding, System.monotonic_time(:millisecond)})
  end

  defp maybe_evict do
    max_size = config()[:max_size] || @default_max_size
    current_size = :ets.info(@table_name, :size)

    if current_size > max_size do
      # Simple eviction: delete oldest 10% of entries
      to_delete = div(max_size, 10)
      evict_oldest(to_delete)
    end
  end

  defp evict_oldest(count) do
    # Get all entries sorted by timestamp (oldest first)
    all_entries = :ets.tab2list(@table_name)

    entries =
      all_entries
      |> Enum.sort_by(fn {_key, _embedding, timestamp} -> timestamp end)
      |> Enum.take(count)

    Enum.each(entries, fn {key, _embedding, _timestamp} ->
      :ets.delete(@table_name, key)
    end)
  end

  defp config do
    Application.get_env(:chatbot, :memory, [])
  end
end
