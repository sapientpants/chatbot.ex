defmodule Chatbot.MCP.ToolRegistry do
  @moduledoc """
  Aggregates tools from all enabled MCP servers for a user.

  - Queries each server for available tools
  - Filters based on user's enabled/disabled tool preferences
  - Formats tool definitions for Ollama API format
  - Resolves which server provides a given tool
  """

  alias Chatbot.MCP
  alias Chatbot.MCP.ClientRegistry
  alias Chatbot.MCP.Server

  require Logger

  @type tool_definition :: %{
          type: String.t(),
          function: %{
            name: String.t(),
            description: String.t(),
            parameters: map()
          }
        }

  @type tool_info :: %{
          server_id: binary(),
          server_name: String.t(),
          tool: map()
        }

  @doc """
  Gets all enabled tools for a user, formatted for Ollama API.
  Returns a list of tool definitions in OpenAI-compatible format.
  """
  @spec get_tools_for_user(binary()) :: {:ok, [tool_definition()]} | {:error, term()}
  def get_tools_for_user(user_id) do
    servers = MCP.list_servers_for_user(user_id)

    tools =
      servers
      |> Enum.flat_map(fn server ->
        case get_server_tools(server) do
          {:ok, server_tools} ->
            filter_enabled_tools(server_tools, user_id, server.id)

          {:error, reason} ->
            Logger.warning("Failed to get tools from server #{server.name}: #{inspect(reason)}")

            []
        end
      end)
      |> Enum.map(&format_tool_for_ollama/1)

    {:ok, tools}
  end

  @doc """
  Gets raw tool info with server mapping for a user.
  Useful for resolving which server to call for a given tool.
  """
  @spec get_tool_mapping(binary()) :: {:ok, %{String.t() => tool_info()}} | {:error, term()}
  def get_tool_mapping(user_id) do
    servers = MCP.list_servers_for_user(user_id)

    mapping =
      servers
      |> Enum.flat_map(fn server ->
        case get_server_tools(server) do
          {:ok, server_tools} ->
            enabled_tools = filter_enabled_tools(server_tools, user_id, server.id)

            Enum.map(enabled_tools, fn tool ->
              {tool["name"],
               %{
                 server_id: server.id,
                 server_name: server.name,
                 tool: tool
               }}
            end)

          {:error, _reason} ->
            []
        end
      end)
      |> Map.new()

    {:ok, mapping}
  end

  @doc """
  Resolves which server provides a tool and returns the client.
  """
  @spec resolve_tool(String.t(), binary()) ::
          {:ok, pid(), Server.t()} | {:error, :tool_not_found | term()}
  def resolve_tool(tool_name, user_id) do
    case get_tool_mapping(user_id) do
      {:ok, mapping} ->
        case Map.get(mapping, tool_name) do
          nil ->
            {:error, :tool_not_found}

          %{server_id: server_id} ->
            server = MCP.get_server!(server_id)

            case ClientRegistry.get_client(server) do
              {:ok, client} -> {:ok, client, server}
              error -> error
            end
        end

      error ->
        error
    end
  end

  @doc """
  Checks if a user has any tools available.
  """
  @spec user_has_tools?(binary()) :: boolean()
  def user_has_tools?(user_id) do
    case get_tools_for_user(user_id) do
      {:ok, []} -> false
      {:ok, _tools} -> true
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_server_tools(%Server{} = server) do
    case ClientRegistry.get_client(server) do
      {:ok, _client} ->
        try do
          # Call list_tools on the dynamically created client module
          client_module = get_client_module(server.id)

          case client_module.list_tools() do
            {:ok, %{result: %{"tools" => tools}}} ->
              ClientRegistry.record_success(server.id)
              {:ok, tools}

            {:ok, %{"tools" => tools}} ->
              ClientRegistry.record_success(server.id)
              {:ok, tools}

            {:error, reason} ->
              ClientRegistry.record_failure(server.id)
              {:error, reason}

            other ->
              Logger.warning("Unexpected list_tools response: #{inspect(other)}")
              {:ok, []}
          end
        rescue
          e ->
            ClientRegistry.record_failure(server.id)
            {:error, e}
        end

      {:error, :circuit_open} ->
        Logger.debug("Circuit open for server #{server.name}, skipping")
        {:error, :circuit_open}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_client_module(server_id) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat([Chatbot.MCP.Client, "Server_#{String.replace(server_id, "-", "_")}"])
  end

  defp filter_enabled_tools(tools, user_id, server_id) do
    Enum.filter(tools, fn tool ->
      MCP.tool_enabled?(user_id, server_id, tool["name"])
    end)
  end

  defp format_tool_for_ollama(tool) do
    %{
      "type" => "function",
      "function" => %{
        "name" => tool["name"],
        "description" => tool["description"] || "",
        "parameters" => tool["inputSchema"] || %{"type" => "object", "properties" => %{}}
      }
    }
  end
end
