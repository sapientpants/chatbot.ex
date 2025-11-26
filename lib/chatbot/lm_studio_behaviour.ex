defmodule Chatbot.LMStudioBehaviour do
  @moduledoc """
  Behaviour definition for LM Studio API client.

  This allows for mocking the LMStudio module in tests using Mox.
  """

  @callback list_models() :: {:ok, [map()]} | {:error, String.t()}
  @callback stream_chat_completion(list(map()), String.t(), pid()) :: :ok | {:error, String.t()}
  @callback chat_completion(list(map()), String.t()) :: {:ok, map()} | {:error, String.t()}
end
