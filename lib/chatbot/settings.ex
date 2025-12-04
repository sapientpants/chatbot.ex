defmodule Chatbot.Settings do
  @moduledoc """
  GenServer for managing system settings with ETS caching.

  Provides fast read access via ETS cache while persisting changes to the database.
  Settings are automatically loaded from the database on startup.

  ## Default Settings

  | Key | Default | Description |
  |-----|---------|-------------|
  | `completion_provider` | `"ollama"` | Which provider handles chat completions |
  | `embedding_provider` | `"ollama"` | Which provider handles embeddings |
  | `default_model` | `nil` | Default model for RAG operations (reranking, query expansion) |
  | `ollama_url` | `"http://localhost:11434"` | Ollama server URL |
  | `ollama_embedding_model` | `"qwen3-embedding:0.6b"` | Default embedding model |
  | `lmstudio_enabled` | `"false"` | Whether LM Studio is enabled |
  | `lmstudio_url` | `"http://localhost:1234/v1"` | LM Studio server URL |

  ## Usage

      # Get a setting (uses ETS cache for fast reads)
      Chatbot.Settings.get("completion_provider")
      #=> "ollama"

      # Set a setting (updates both ETS and database)
      Chatbot.Settings.set("completion_provider", "lmstudio")
      #=> :ok

      # Get all settings as a map
      Chatbot.Settings.all()
      #=> %{"completion_provider" => "ollama", ...}

  """

  use GenServer

  alias Chatbot.Repo
  alias Chatbot.SystemSetting

  require Logger

  @ets_table :chatbot_settings
  @defaults %{
    "completion_provider" => "ollama",
    "embedding_provider" => "ollama",
    "default_model" => nil,
    "ollama_url" => "http://localhost:11434",
    "ollama_embedding_model" => "qwen3-embedding:0.6b",
    "lmstudio_enabled" => "false",
    "lmstudio_url" => "http://localhost:1234/v1"
  }

  # Client API

  @doc """
  Starts the Settings GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a setting value by key.

  Returns the cached value from ETS for fast access.
  Falls back to the default value if not set.

  ## Examples

      iex> Chatbot.Settings.get("completion_provider")
      "ollama"

      iex> Chatbot.Settings.get("unknown_key")
      nil

  """
  @spec get(String.t()) :: String.t() | nil
  def get(key) when is_binary(key) do
    case :ets.lookup(@ets_table, key) do
      [{^key, value}] -> value
      [] -> Map.get(@defaults, key)
    end
  end

  @doc """
  Gets a setting value, returning the provided default if not set.

  ## Examples

      iex> Chatbot.Settings.get("unknown_key", "default")
      "default"

  """
  @spec get(String.t(), String.t() | nil) :: String.t() | nil
  def get(key, default) when is_binary(key) do
    case :ets.lookup(@ets_table, key) do
      [{^key, value}] -> value
      [] -> Map.get(@defaults, key, default)
    end
  end

  @doc """
  Gets a boolean setting value.

  ## Examples

      iex> Chatbot.Settings.get_boolean("lmstudio_enabled")
      false

  """
  @spec get_boolean(String.t()) :: boolean()
  def get_boolean(key) when is_binary(key) do
    get(key) == "true"
  end

  @doc """
  Sets a setting value.

  Updates both the ETS cache and the database.

  ## Examples

      iex> Chatbot.Settings.set("completion_provider", "lmstudio")
      :ok

  """
  @spec set(String.t(), String.t()) :: :ok | {:error, term()}
  def set(key, value) when is_binary(key) and is_binary(value) do
    GenServer.call(__MODULE__, {:set, key, value})
  end

  @doc """
  Sets multiple settings at once.

  ## Examples

      iex> Chatbot.Settings.set_many(%{"completion_provider" => "lmstudio", "lmstudio_enabled" => "true"})
      :ok

  """
  @spec set_many(map()) :: :ok | {:error, term()}
  def set_many(settings) when is_map(settings) do
    GenServer.call(__MODULE__, {:set_many, settings})
  end

  @doc """
  Returns all settings as a map.

  Combines defaults with any explicitly set values.
  """
  @spec all() :: map()
  def all do
    cached =
      @ets_table
      |> :ets.tab2list()
      |> Map.new()

    Map.merge(@defaults, cached)
  end

  @doc """
  Returns the default values for all settings.
  """
  @spec defaults() :: %{String.t() => String.t()}
  def defaults, do: @defaults

  @doc """
  Reloads settings from the database into the ETS cache.
  """
  @spec reload() :: :ok
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # Server Callbacks

  @impl GenServer
  def init(_opts) do
    # Create ETS table for fast reads
    :ets.new(@ets_table, [:named_table, :public, read_concurrency: true])

    # Load settings from database
    load_from_database()

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:set, key, value}, _from, state) do
    result = save_setting(key, value)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:set_many, settings}, _from, state) do
    result =
      Repo.transaction(fn ->
        Enum.each(settings, fn {key, value} ->
          case save_setting(key, value) do
            :ok -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
      end)

    case result do
      {:ok, _result} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:reload, _from, state) do
    load_from_database()
    {:reply, :ok, state}
  end

  # Private Functions

  defp load_from_database do
    # Only try to load if the Repo is started (skip during tests before sandbox is ready)
    if Process.whereis(Repo) do
      try do
        import Ecto.Query

        settings =
          SystemSetting
          |> select([s], {s.key, s.value})
          |> Repo.all()

        # Clear existing cache and load fresh data
        :ets.delete_all_objects(@ets_table)

        Enum.each(settings, fn {key, value} ->
          :ets.insert(@ets_table, {key, value})
        end)

        Logger.debug("Loaded #{length(settings)} settings from database")
      rescue
        e ->
          Logger.warning("Failed to load settings from database: #{Exception.message(e)}")
      end
    else
      Logger.debug("Repo not started, using default settings")
    end
  end

  defp save_setting(key, value) do
    result =
      Repo.insert(
        %SystemSetting{key: key, value: value},
        on_conflict: [set: [value: value, updated_at: DateTime.utc_now()]],
        conflict_target: :key
      )

    case result do
      {:ok, _setting} ->
        :ets.insert(@ets_table, {key, value})
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
