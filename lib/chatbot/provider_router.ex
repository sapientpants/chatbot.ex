defmodule Chatbot.ProviderRouter do
  @moduledoc """
  Central routing module for LLM provider access.

  Routes requests to the appropriate provider (Ollama or LM Studio) based on:
  1. Model prefix (e.g., `ollama/llama3` → Ollama, `lmstudio/mistral` → LM Studio)
  2. Configured default provider for unprefixed models

  ## Usage

      # Streaming chat completion (routes based on model prefix)
      ProviderRouter.stream_chat_completion(messages, "ollama/llama3", self())

      # Non-streaming chat completion
      {:ok, response} = ProviderRouter.chat_completion(messages, "lmstudio/mistral")

      # Embeddings (uses configured embedding provider)
      {:ok, embedding} = ProviderRouter.embed("Hello, world!")

      # List all models from enabled providers
      {:ok, models} = ProviderRouter.list_all_models()

  """

  alias Chatbot.LMStudio
  alias Chatbot.Ollama
  alias Chatbot.Settings

  require Logger

  @typedoc "A chat message in OpenAI format"
  @type message :: %{role: String.t(), content: String.t()}

  @typedoc "A list of chat messages"
  @type messages :: [message()]

  # ============================================================================
  # Chat Completion Functions
  # ============================================================================

  @doc """
  Sends a streaming chat completion request to the appropriate provider.

  The provider is determined by the model prefix (e.g., `ollama/`, `lmstudio/`).
  If no prefix is present, uses the configured completion provider.

  ## Parameters
    - messages: List of messages in OpenAI format
    - model: Model name with optional provider prefix
    - pid: Process ID to send streaming chunks to

  ## Examples

      iex> stream_chat_completion([%{role: "user", content: "Hi"}], "ollama/llama3", self())
      :ok

  """
  @spec stream_chat_completion(messages(), String.t(), pid()) :: :ok | {:error, String.t()}
  def stream_chat_completion(messages, model, pid) do
    {provider, model_name} = parse_model(model)

    case provider do
      :ollama -> ollama_client().stream_chat_completion(messages, model_name, pid)
      :lmstudio -> lm_studio_client().stream_chat_completion(messages, model_name, pid)
    end
  end

  @doc """
  Sends a non-streaming chat completion request to the appropriate provider.

  ## Parameters
    - messages: List of messages in OpenAI format
    - model: Model name with optional provider prefix

  ## Returns
    - `{:ok, response}` with the completion in OpenAI-compatible format
    - `{:error, reason}` on failure

  ## Examples

      iex> chat_completion([%{role: "user", content: "Hello"}], "ollama/llama3")
      {:ok, %{"choices" => [%{"message" => %{"content" => "Hi!"}}]}}

  """
  @spec chat_completion(messages(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def chat_completion(messages, model) do
    {provider, model_name} = parse_model(model)

    case provider do
      :ollama -> ollama_client().chat_completion(messages, model_name)
      :lmstudio -> lm_studio_client().chat_completion(messages, model_name)
    end
  end

  @doc """
  Sends a non-streaming chat completion request with tool definitions.

  This is used for tool-enabled conversations where the LLM may return
  tool_calls that need to be executed.

  ## Parameters
    - messages: List of messages in OpenAI format
    - tools: List of tool definitions in OpenAI format
    - opts: Keyword options
      - `:model` - Model name with optional provider prefix (required)

  ## Returns
    - `{:ok, response}` with the completion including potential tool_calls
    - `{:error, reason}` on failure

  ## Examples

      tools = [%{"type" => "function", "function" => %{"name" => "get_weather", ...}}]
      {:ok, response} = chat_completion_with_tools(messages, tools, model: "ollama/llama3")

  """
  @spec chat_completion_with_tools(messages(), [map()], keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def chat_completion_with_tools(messages, tools, opts) do
    model = Keyword.fetch!(opts, :model)
    {provider, model_name} = parse_model(model)

    case provider do
      :ollama ->
        ollama_client().chat_with_tools(messages, tools, model_name)

      :lmstudio ->
        # LM Studio may support tools through OpenAI-compatible API
        lm_studio_client().chat_with_tools(messages, tools, model_name)
    end
  end

  # ============================================================================
  # Embedding Functions
  # ============================================================================

  @doc """
  Generates an embedding vector for the given text.

  Uses the configured embedding provider (Ollama by default).

  ## Parameters
    - text: The text to generate an embedding for

  ## Returns
    - `{:ok, embedding}` where embedding is a list of floats
    - `{:error, reason}` on failure

  """
  @spec embed(String.t()) :: {:ok, [float()]} | {:error, String.t()}
  def embed(text) do
    case embedding_provider() do
      :ollama -> ollama_client().embed(text)
      :lmstudio -> {:error, "LM Studio embedding not yet supported"}
    end
  end

  @doc """
  Generates embedding vectors for multiple texts in a single request.

  Uses the configured embedding provider (Ollama by default).

  ## Parameters
    - texts: List of texts to generate embeddings for

  ## Returns
    - `{:ok, embeddings}` where embeddings is a list of embedding vectors
    - `{:error, reason}` on failure

  """
  @spec embed_batch([String.t()]) :: {:ok, [[float()]]} | {:error, String.t()}
  def embed_batch(texts) do
    case embedding_provider() do
      :ollama -> ollama_client().embed_batch(texts)
      :lmstudio -> {:error, "LM Studio embedding not yet supported"}
    end
  end

  @doc """
  Returns the embedding dimension for the current embedding provider.
  """
  @spec embedding_dimension() :: pos_integer()
  def embedding_dimension do
    case embedding_provider() do
      :ollama -> ollama_client().embedding_dimension()
      :lmstudio -> 1024
    end
  end

  # ============================================================================
  # Model Listing Functions
  # ============================================================================

  @doc """
  Lists all available models from all enabled providers.

  Returns models with provider prefix (e.g., `ollama/llama3`, `lmstudio/mistral`).

  ## Returns
    - `{:ok, models}` list of model info maps
    - `{:error, reason}` if all providers fail

  """
  @spec list_all_models() :: {:ok, [map()]} | {:error, String.t()}
  def list_all_models do
    # Always try Ollama (required provider)
    ollama_result = ollama_client().list_models()

    # Try LM Studio only if enabled
    lmstudio_result =
      if lmstudio_enabled?() do
        lm_studio_client().list_models()
      else
        {:ok, []}
      end

    case {ollama_result, lmstudio_result} do
      {{:ok, ollama_models}, {:ok, lmstudio_models}} ->
        {:ok, ollama_models ++ prefix_lmstudio_models(lmstudio_models)}

      {{:ok, ollama_models}, {:error, _lmstudio_err}} ->
        Logger.warning("LM Studio model fetch failed, using Ollama models only")
        {:ok, ollama_models}

      {{:error, _ollama_err}, {:ok, lmstudio_models}} ->
        Logger.warning("Ollama model fetch failed, using LM Studio models only")
        {:ok, prefix_lmstudio_models(lmstudio_models)}

      {{:error, ollama_err}, {:error, _lmstudio_err}} ->
        {:error, ollama_err}
    end
  end

  # ============================================================================
  # Provider Configuration
  # ============================================================================

  @doc """
  Returns the currently configured completion provider.
  """
  @spec completion_provider() :: :ollama | :lmstudio
  def completion_provider do
    case Settings.get("completion_provider") do
      "lmstudio" -> :lmstudio
      _other -> :ollama
    end
  end

  @doc """
  Returns the currently configured embedding provider.
  """
  @spec embedding_provider() :: :ollama | :lmstudio
  def embedding_provider do
    case Settings.get("embedding_provider") do
      "lmstudio" -> :lmstudio
      _other -> :ollama
    end
  end

  @doc """
  Returns whether LM Studio is enabled.
  """
  @spec lmstudio_enabled?() :: boolean()
  def lmstudio_enabled? do
    Settings.get_boolean("lmstudio_enabled")
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Add provider prefix to LM Studio models
  defp prefix_lmstudio_models(models) do
    Enum.map(models, fn model ->
      id = model["id"] || model["name"]

      Map.merge(model, %{
        "id" => "lmstudio/#{id}",
        "provider" => "lmstudio"
      })
    end)
  end

  # Parse model string to determine provider and clean model name
  defp parse_model(model) when is_binary(model) do
    case String.split(model, "/", parts: 2) do
      ["ollama", name] -> {:ollama, name}
      ["lmstudio", name] -> {:lmstudio, name}
      _other -> {completion_provider(), model}
    end
  end

  # Client accessors for dependency injection in tests
  defp ollama_client do
    Application.get_env(:chatbot, :ollama_client, Ollama)
  end

  defp lm_studio_client do
    Application.get_env(:chatbot, :lm_studio_client, LMStudio)
  end
end
