defmodule Chatbot.MCP do
  @moduledoc """
  Context module for MCP server and tool configuration management.
  """

  import Ecto.Query

  alias Chatbot.Accounts.User
  alias Chatbot.MCP.Server
  alias Chatbot.MCP.UserToolConfig
  alias Chatbot.Repo

  # ============================================================================
  # MCP Servers
  # ============================================================================

  @doc """
  Lists all MCP servers available to a user (global + user-specific).
  """
  @spec list_servers_for_user(binary()) :: [Server.t()]
  def list_servers_for_user(user_id) do
    Server
    |> where([s], s.global == true or s.user_id == ^user_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists enabled MCP servers for a user (global + user-specific).
  """
  @spec get_enabled_servers_for_user(binary()) :: [Server.t()]
  def get_enabled_servers_for_user(user_id) do
    Server
    |> where([s], s.global == true or s.user_id == ^user_id)
    |> where([s], s.enabled == true)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists all MCP servers owned by a user.
  """
  @spec list_user_servers(binary()) :: [Server.t()]
  def list_user_servers(user_id) do
    Server
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists all global MCP servers.
  """
  @spec list_global_servers() :: [Server.t()]
  def list_global_servers do
    Server
    |> where([s], s.global == true)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Gets an MCP server by ID.
  """
  @spec get_server(binary()) :: Server.t() | nil
  def get_server(id), do: Repo.get(Server, id)

  @doc """
  Gets an MCP server by ID, raises if not found.
  """
  @spec get_server!(binary()) :: Server.t()
  def get_server!(id), do: Repo.get!(Server, id)

  @doc """
  Creates an MCP server.
  """
  @spec create_server(map()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t()}
  def create_server(attrs) do
    %Server{}
    |> Server.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a global MCP server (admin only).
  """
  @spec create_global_server(map()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t()}
  def create_global_server(attrs) do
    attrs
    |> stringify_keys()
    |> Map.put("global", true)
    |> Map.delete("user_id")
    |> then(&create_server/1)
  end

  @doc """
  Creates a user-specific MCP server.
  """
  @spec create_user_server(User.t() | binary(), map()) ::
          {:ok, Server.t()} | {:error, Ecto.Changeset.t()}
  def create_user_server(%User{id: user_id}, attrs), do: create_user_server(user_id, attrs)

  def create_user_server(user_id, attrs) when is_binary(user_id) do
    attrs
    |> stringify_keys()
    |> Map.put("user_id", user_id)
    |> Map.put("global", false)
    |> then(&create_server/1)
  end

  # Converts a map's atom keys to string keys
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  @doc """
  Updates an MCP server.
  """
  @spec update_server(Server.t(), map()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t()}
  def update_server(%Server{} = server, attrs) do
    server
    |> Server.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an MCP server.
  """
  @spec delete_server(Server.t()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t()}
  def delete_server(%Server{} = server) do
    Repo.delete(server)
  end

  # ============================================================================
  # User Tool Configurations
  # ============================================================================

  @doc """
  Lists all tool configurations for a user.
  """
  @spec list_user_tool_configs(binary()) :: [UserToolConfig.t()]
  def list_user_tool_configs(user_id) do
    UserToolConfig
    |> where([c], c.user_id == ^user_id)
    |> preload(:mcp_server)
    |> Repo.all()
  end

  @doc """
  Lists enabled tools for a user from a specific server.
  """
  @spec list_enabled_tools_for_server(binary(), binary()) :: [String.t()]
  def list_enabled_tools_for_server(user_id, server_id) do
    UserToolConfig
    |> where([c], c.user_id == ^user_id and c.mcp_server_id == ^server_id and c.enabled == true)
    |> select([c], c.tool_name)
    |> Repo.all()
  end

  @doc """
  Gets a specific tool configuration.
  """
  @spec get_tool_config(binary(), binary(), String.t()) :: UserToolConfig.t() | nil
  def get_tool_config(user_id, server_id, tool_name) do
    UserToolConfig
    |> where(
      [c],
      c.user_id == ^user_id and c.mcp_server_id == ^server_id and c.tool_name == ^tool_name
    )
    |> Repo.one()
  end

  @doc """
  Enables a tool for a user.
  """
  @spec enable_tool(binary(), binary(), String.t()) ::
          {:ok, UserToolConfig.t()} | {:error, Ecto.Changeset.t()}
  def enable_tool(user_id, server_id, tool_name) do
    case get_tool_config(user_id, server_id, tool_name) do
      nil ->
        create_tool_config(%{
          user_id: user_id,
          mcp_server_id: server_id,
          tool_name: tool_name,
          enabled: true
        })

      config ->
        update_tool_config(config, %{enabled: true})
    end
  end

  @doc """
  Disables a tool for a user.
  """
  @spec disable_tool(binary(), binary(), String.t()) ::
          {:ok, UserToolConfig.t()} | {:error, Ecto.Changeset.t()}
  def disable_tool(user_id, server_id, tool_name) do
    case get_tool_config(user_id, server_id, tool_name) do
      nil ->
        create_tool_config(%{
          user_id: user_id,
          mcp_server_id: server_id,
          tool_name: tool_name,
          enabled: false
        })

      config ->
        update_tool_config(config, %{enabled: false})
    end
  end

  @doc """
  Checks if a tool is enabled for a user.
  """
  @spec tool_enabled?(binary(), binary(), String.t()) :: boolean()
  def tool_enabled?(user_id, server_id, tool_name) do
    case get_tool_config(user_id, server_id, tool_name) do
      nil -> true
      config -> config.enabled
    end
  end

  @doc """
  Creates a tool configuration.
  """
  @spec create_tool_config(map()) :: {:ok, UserToolConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_tool_config(attrs) do
    %UserToolConfig{}
    |> UserToolConfig.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a tool configuration.
  """
  @spec update_tool_config(UserToolConfig.t(), map()) ::
          {:ok, UserToolConfig.t()} | {:error, Ecto.Changeset.t()}
  def update_tool_config(%UserToolConfig{} = config, attrs) do
    config
    |> UserToolConfig.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Checks if a user has any tools enabled across all servers.
  """
  @spec user_has_tools_enabled?(binary()) :: boolean()
  def user_has_tools_enabled?(user_id) do
    servers = list_servers_for_user(user_id)

    Enum.any?(servers, fn server ->
      configs = list_user_tool_configs(user_id)
      server_configs = Enum.filter(configs, &(&1.mcp_server_id == server.id))

      case server_configs do
        [] -> true
        configs -> Enum.any?(configs, & &1.enabled)
      end
    end)
  end
end
