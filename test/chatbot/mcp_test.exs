defmodule Chatbot.MCPTest do
  @moduledoc """
  Tests for MCP context module - server and tool config management.
  """
  use Chatbot.DataCase

  alias Chatbot.MCP
  alias Chatbot.MCP.Server
  alias Chatbot.MCP.UserToolConfig

  import Chatbot.Fixtures

  describe "servers" do
    setup do
      user = user_fixture()
      {:ok, user: user}
    end

    test "create_user_server/2 creates a STDIO server for user", %{user: user} do
      attrs = %{
        "name" => "Test Server",
        "transport_type" => "stdio",
        "command" => "npx test-server",
        "description" => "A test server"
      }

      assert {:ok, server} = MCP.create_user_server(user.id, attrs)
      assert server.name == "Test Server"
      assert server.transport_type == "stdio"
      assert server.command == "npx test-server"
      assert server.user_id == user.id
      assert server.global == false
      assert server.enabled == true
    end

    test "create_user_server/2 creates an HTTP server for user", %{user: user} do
      attrs = %{
        "name" => "Remote Server",
        "transport_type" => "http",
        "base_url" => "http://localhost:3000"
      }

      assert {:ok, server} = MCP.create_user_server(user.id, attrs)
      assert server.transport_type == "http"
      assert server.base_url == "http://localhost:3000"
    end

    test "create_user_server/2 returns error for invalid data", %{user: user} do
      attrs = %{"name" => "", "transport_type" => "invalid"}
      assert {:error, changeset} = MCP.create_user_server(user.id, attrs)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "list_servers_for_user/1 returns user servers and global servers", %{user: user} do
      # Create a user server
      {:ok, user_server} =
        MCP.create_user_server(user.id, %{
          "name" => "User Server",
          "transport_type" => "stdio",
          "command" => "test"
        })

      # Create a global server
      {:ok, global_server} =
        MCP.create_global_server(%{
          "name" => "Global Server",
          "transport_type" => "http",
          "base_url" => "http://global.test"
        })

      servers = MCP.list_servers_for_user(user.id)
      server_ids = Enum.map(servers, & &1.id)

      assert user_server.id in server_ids
      assert global_server.id in server_ids
    end

    test "list_user_servers/1 returns only user's own servers", %{user: user} do
      {:ok, user_server} =
        MCP.create_user_server(user.id, %{
          "name" => "My Server",
          "transport_type" => "stdio",
          "command" => "test"
        })

      {:ok, _global} =
        MCP.create_global_server(%{
          "name" => "Global",
          "transport_type" => "http",
          "base_url" => "http://test"
        })

      servers = MCP.list_user_servers(user.id)
      assert length(servers) == 1
      assert hd(servers).id == user_server.id
    end

    test "get_server!/1 returns the server", %{user: user} do
      {:ok, server} =
        MCP.create_user_server(user.id, %{
          "name" => "Test",
          "transport_type" => "stdio",
          "command" => "test"
        })

      fetched = MCP.get_server!(server.id)
      assert fetched.id == server.id
    end

    test "delete_server/1 removes the server", %{user: user} do
      {:ok, server} =
        MCP.create_user_server(user.id, %{
          "name" => "Test",
          "transport_type" => "stdio",
          "command" => "test"
        })

      assert {:ok, _deleted} = MCP.delete_server(server)
      assert_raise Ecto.NoResultsError, fn -> MCP.get_server!(server.id) end
    end

    test "get_enabled_servers_for_user/1 returns only enabled servers", %{user: user} do
      {:ok, enabled_server} =
        MCP.create_user_server(user.id, %{
          "name" => "Enabled",
          "transport_type" => "stdio",
          "command" => "test"
        })

      {:ok, disabled_server} =
        MCP.create_user_server(user.id, %{
          "name" => "Disabled",
          "transport_type" => "stdio",
          "command" => "test2",
          "enabled" => false
        })

      servers = MCP.get_enabled_servers_for_user(user.id)
      server_ids = Enum.map(servers, & &1.id)

      assert enabled_server.id in server_ids
      refute disabled_server.id in server_ids
    end
  end

  describe "tool configs" do
    setup do
      user = user_fixture()

      {:ok, server} =
        MCP.create_user_server(user.id, %{
          "name" => "Test Server",
          "transport_type" => "stdio",
          "command" => "test"
        })

      {:ok, user: user, server: server}
    end

    test "enable_tool/3 creates a config with enabled=true", %{user: user, server: server} do
      assert {:ok, config} = MCP.enable_tool(user.id, server.id, "test_tool")
      assert config.enabled == true
      assert config.tool_name == "test_tool"
    end

    test "disable_tool/3 creates a config with enabled=false", %{user: user, server: server} do
      assert {:ok, config} = MCP.disable_tool(user.id, server.id, "test_tool")
      assert config.enabled == false
    end

    test "tool_enabled?/3 returns true by default", %{user: user, server: server} do
      assert MCP.tool_enabled?(user.id, server.id, "unknown_tool") == true
    end

    test "tool_enabled?/3 returns false when explicitly disabled", %{user: user, server: server} do
      MCP.disable_tool(user.id, server.id, "disabled_tool")
      assert MCP.tool_enabled?(user.id, server.id, "disabled_tool") == false
    end

    test "list_user_tool_configs/1 returns all configs for user", %{user: user, server: server} do
      MCP.enable_tool(user.id, server.id, "tool1")
      MCP.disable_tool(user.id, server.id, "tool2")

      configs = MCP.list_user_tool_configs(user.id)
      assert length(configs) == 2
    end
  end

  describe "Server schema" do
    test "changeset validates required fields" do
      changeset = Server.changeset(%Server{}, %{})
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).transport_type
    end

    test "changeset validates transport_type values" do
      changeset = Server.changeset(%Server{}, %{transport_type: "invalid"})
      assert "is invalid" in errors_on(changeset).transport_type
    end

    test "changeset validates command required for stdio" do
      changeset =
        Server.changeset(%Server{}, %{
          name: "Test",
          transport_type: "stdio"
        })

      assert "can't be blank" in errors_on(changeset).command
    end

    test "changeset validates base_url required for http" do
      changeset =
        Server.changeset(%Server{}, %{
          name: "Test",
          transport_type: "http"
        })

      assert "can't be blank" in errors_on(changeset).base_url
    end
  end

  describe "UserToolConfig schema" do
    test "changeset validates required fields" do
      changeset = UserToolConfig.changeset(%UserToolConfig{}, %{})
      assert "can't be blank" in errors_on(changeset).tool_name
    end
  end

  describe "user_has_tools_enabled?/1" do
    setup do
      user = user_fixture()
      {:ok, user: user}
    end

    test "returns false when no servers exist", %{user: user} do
      refute MCP.user_has_tools_enabled?(user.id)
    end

    test "returns true when enabled server exists", %{user: user} do
      {:ok, _server} =
        MCP.create_user_server(user.id, %{
          "name" => "Test Server",
          "transport_type" => "stdio",
          "command" => "test"
        })

      assert MCP.user_has_tools_enabled?(user.id)
    end
  end

  describe "get_server/1" do
    setup do
      user = user_fixture()

      {:ok, server} =
        MCP.create_user_server(user.id, %{
          "name" => "Test",
          "transport_type" => "stdio",
          "command" => "test"
        })

      {:ok, server: server}
    end

    test "returns server when found", %{server: server} do
      assert MCP.get_server(server.id) != nil
    end

    test "returns nil when not found" do
      assert MCP.get_server(Ecto.UUID.generate()) == nil
    end
  end

  describe "update_server/2" do
    setup do
      user = user_fixture()

      {:ok, server} =
        MCP.create_user_server(user.id, %{
          "name" => "Original",
          "transport_type" => "stdio",
          "command" => "test"
        })

      {:ok, server: server}
    end

    test "updates server attributes", %{server: server} do
      {:ok, updated} = MCP.update_server(server, %{"name" => "Updated"})
      assert updated.name == "Updated"
    end
  end

  describe "list_enabled_tools_for_server/2" do
    setup do
      user = user_fixture()

      {:ok, server} =
        MCP.create_user_server(user.id, %{
          "name" => "Test",
          "transport_type" => "stdio",
          "command" => "test"
        })

      {:ok, user: user, server: server}
    end

    test "returns enabled tool names", %{user: user, server: server} do
      MCP.enable_tool(user.id, server.id, "tool1")
      MCP.enable_tool(user.id, server.id, "tool2")
      MCP.disable_tool(user.id, server.id, "tool3")

      tools = MCP.list_enabled_tools_for_server(user.id, server.id)
      assert "tool1" in tools
      assert "tool2" in tools
      refute "tool3" in tools
    end
  end
end
