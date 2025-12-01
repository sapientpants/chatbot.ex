defmodule Chatbot.Ollama.ResponseFormatter do
  @moduledoc """
  Formats Ollama API responses to OpenAI-compatible format.

  Ollama has its own response format that differs from OpenAI's API.
  This module provides functions to convert Ollama responses to
  the standardized OpenAI format used throughout the application.
  """

  @doc """
  Converts an Ollama chat response to OpenAI-compatible format.

  ## Parameters

  - `message` - The message object from Ollama's response
  - `response` - The full response from Ollama
  - `model_name` - The model name to include in the response

  ## Examples

      iex> format_chat_response(%{"content" => "Hello"}, %{"done" => true}, "llama3")
      %{
        "choices" => [%{"index" => 0, "message" => %{"role" => "assistant", "content" => "Hello"}, "finish_reason" => "stop"}],
        "model" => "llama3",
        "usage" => %{"prompt_tokens" => 0, "completion_tokens" => 0, "total_tokens" => 0}
      }

  """
  @spec format_chat_response(map(), map(), String.t()) :: map()
  def format_chat_response(message, response, model_name) do
    %{
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => message["role"] || "assistant",
            "content" => message["content"] || ""
          },
          "finish_reason" => if(response["done"], do: "stop", else: nil)
        }
      ],
      "model" => model_name,
      "usage" => format_usage(response)
    }
  end

  @doc """
  Converts an Ollama tool response to OpenAI-compatible format.

  Handles tool_calls in the response message and formats them
  according to OpenAI's tool calling specification.

  ## Parameters

  - `message` - The message object from Ollama's response (may include tool_calls)
  - `response` - The full response from Ollama
  - `model_name` - The model name to include in the response

  """
  @spec format_tool_response(map(), map(), String.t()) :: map()
  def format_tool_response(message, response, model_name) do
    tool_calls = message["tool_calls"]

    message_content = %{
      "role" => message["role"] || "assistant",
      "content" => message["content"] || ""
    }

    message_with_tools =
      if tool_calls && length(tool_calls) > 0 do
        formatted_calls = Enum.map(tool_calls, &format_tool_call/1)
        Map.put(message_content, "tool_calls", formatted_calls)
      else
        message_content
      end

    finish_reason =
      cond do
        tool_calls && length(tool_calls) > 0 -> "tool_calls"
        response["done"] -> "stop"
        true -> nil
      end

    %{
      "choices" => [
        %{
          "index" => 0,
          "message" => message_with_tools,
          "finish_reason" => finish_reason
        }
      ],
      "model" => model_name,
      "usage" => format_usage(response)
    }
  end

  @doc """
  Converts OpenAI-format tools to Ollama format.

  Ollama uses the same tool format as OpenAI, but we normalize
  to ensure consistency.

  ## Parameters

  - `tools` - List of tools in OpenAI format

  ## Examples

      iex> convert_tools_to_ollama([%{"type" => "function", "function" => %{"name" => "get_weather"}}])
      [%{"type" => "function", "function" => %{"name" => "get_weather", "description" => "", "parameters" => %{"type" => "object", "properties" => %{}}}}]

  """
  @spec convert_tools_to_ollama([map()]) :: [map()]
  def convert_tools_to_ollama(tools) do
    Enum.map(tools, &convert_tool/1)
  end

  @doc """
  Formats model list response with provider prefix.

  ## Parameters

  - `models` - List of models from Ollama's /api/tags endpoint
  - `provider_prefix` - Prefix to add to model IDs (e.g., "ollama/")

  """
  @spec format_model_list([map()], String.t()) :: [map()]
  def format_model_list(models, provider_prefix) do
    Enum.map(models, fn model ->
      name = model["name"] || model["model"]

      %{
        "id" => provider_prefix <> name,
        "name" => name,
        "provider" => "ollama",
        "size" => model["size"],
        "modified_at" => model["modified_at"]
      }
    end)
  end

  # Private helpers

  defp format_usage(response) do
    prompt_tokens = response["prompt_eval_count"] || 0
    completion_tokens = response["eval_count"] || 0

    %{
      "prompt_tokens" => prompt_tokens,
      "completion_tokens" => completion_tokens,
      "total_tokens" => prompt_tokens + completion_tokens
    }
  end

  defp format_tool_call(call) do
    %{
      "id" => call["id"] || generate_tool_call_id(),
      "type" => "function",
      "function" => %{
        "name" => get_in(call, ["function", "name"]) || call["name"],
        "arguments" =>
          get_in(call, ["function", "arguments"]) ||
            Jason.encode!(call["arguments"] || %{})
      }
    }
  end

  defp convert_tool(tool) do
    case tool do
      %{"type" => "function", "function" => func} ->
        %{
          "type" => "function",
          "function" => %{
            "name" => func["name"],
            "description" => func["description"] || "",
            "parameters" => func["parameters"] || %{"type" => "object", "properties" => %{}}
          }
        }

      other ->
        other
    end
  end

  defp generate_tool_call_id do
    "call_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
