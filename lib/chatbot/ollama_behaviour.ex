defmodule Chatbot.OllamaBehaviour do
  @moduledoc """
  Behaviour definition for Ollama API client.

  Supports both embeddings and chat completions.
  This allows for mocking the Ollama module in tests using Mox.
  """

  @typedoc "A chat message in OpenAI format"
  @type message :: %{role: String.t(), content: String.t()}

  @typedoc "A list of chat messages"
  @type messages :: [message()]

  @typedoc "Model information from Ollama"
  @type model_info :: %{String.t() => any()}

  # Embedding callbacks
  @callback embed(String.t()) :: {:ok, [float()]} | {:error, String.t()}
  @callback embed_batch([String.t()]) :: {:ok, [[float()]]} | {:error, String.t()}
  @callback embedding_dimension() :: pos_integer()

  # Chat completion callbacks
  @callback list_models() :: {:ok, [model_info()]} | {:error, String.t()}
  @callback chat_completion(messages(), String.t()) :: {:ok, map()} | {:error, String.t()}
  @callback stream_chat_completion(messages(), String.t(), pid()) :: :ok | {:error, String.t()}
end
