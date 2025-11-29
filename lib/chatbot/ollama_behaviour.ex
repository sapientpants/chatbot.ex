defmodule Chatbot.OllamaBehaviour do
  @moduledoc """
  Behaviour definition for Ollama embedding API client.

  This allows for mocking the Ollama module in tests using Mox.
  """

  @callback embed(String.t()) :: {:ok, [float()]} | {:error, String.t()}
  @callback embed_batch([String.t()]) :: {:ok, [[float()]]} | {:error, String.t()}
  @callback embedding_dimension() :: pos_integer()
end
