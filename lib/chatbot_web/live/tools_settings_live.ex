defmodule ChatbotWeb.ToolsSettingsLive do
  @moduledoc """
  Settings page for configuring MCP servers and tools.

  Allows users to:
  - Add/edit/remove MCP server configurations
  - Enable/disable individual tools
  - Test MCP server connections
  """
  use ChatbotWeb, :live_view

  alias Chatbot.MCP
  alias Chatbot.MCP.Server

  require Logger

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id

    socket =
      socket
      |> assign(:servers, MCP.list_servers_for_user(user_id))
      |> assign(:global_servers, MCP.list_global_servers())
      |> assign(:user_servers, MCP.list_user_servers(user_id))
      |> assign(:selected_server, nil)
      |> assign(:server_tools, [])
      |> assign(:tool_configs, MCP.list_user_tool_configs(user_id))
      |> assign(:show_add_server_modal, false)
      |> assign(:server_form, to_form(build_server_changeset(%{}), as: :server))

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-900 text-zinc-100">
      <div class="max-w-4xl mx-auto py-8 px-4">
        <div class="flex items-center justify-between mb-8">
          <div>
            <h1 class="text-2xl font-bold">Tool Settings</h1>
            <p class="text-zinc-400 mt-1">Configure MCP servers and manage available tools</p>
          </div>
          <.link navigate={~p"/settings"} class="text-zinc-400 hover:text-zinc-200">
            Back to Settings
          </.link>
        </div>

        <div class="space-y-6">
          <div class="bg-zinc-800 rounded-lg p-6">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold">MCP Servers</h2>
              <button
                phx-click="show_add_server"
                class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm transition-colors"
              >
                Add Server
              </button>
            </div>

            <div :if={Enum.empty?(@servers)} class="text-zinc-500 text-center py-8">
              No MCP servers configured. Add a server to enable tool calling.
            </div>

            <div :if={not Enum.empty?(@servers)} class="space-y-3">
              <div
                :for={server <- @servers}
                class={[
                  "p-4 rounded-lg border cursor-pointer transition-colors",
                  if(@selected_server && @selected_server.id == server.id,
                    do: "border-blue-500 bg-zinc-700",
                    else: "border-zinc-700 hover:border-zinc-600"
                  )
                ]}
                phx-click="select_server"
                phx-value-id={server.id}
              >
                <div class="flex items-center justify-between">
                  <div>
                    <div class="font-medium flex items-center gap-2">
                      {server.name}
                      <span
                        :if={server.global}
                        class="px-2 py-0.5 bg-zinc-600 text-zinc-300 text-xs rounded"
                      >
                        Global
                      </span>
                    </div>
                    <div class="text-sm text-zinc-400">
                      {server.transport_type |> String.upcase()} - {if server.transport_type ==
                                                                         "stdio",
                                                                       do: server.command,
                                                                       else: server.base_url}
                    </div>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class={[
                      "w-2 h-2 rounded-full",
                      if(server.enabled, do: "bg-green-500", else: "bg-zinc-500")
                    ]} />
                    <button
                      :if={!server.global}
                      phx-click="delete_server"
                      phx-value-id={server.id}
                      class="p-1 text-zinc-500 hover:text-red-400 transition-colors"
                      data-confirm="Are you sure you want to delete this server?"
                    >
                      <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                        />
                      </svg>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div :if={@selected_server} class="bg-zinc-800 rounded-lg p-6">
            <h2 class="text-lg font-semibold mb-4">
              Tools from {@selected_server.name}
            </h2>

            <div :if={Enum.empty?(@server_tools)} class="text-zinc-500 text-center py-4">
              No tools available from this server.
            </div>

            <div :if={not Enum.empty?(@server_tools)} class="space-y-2">
              <div
                :for={tool <- @server_tools}
                class="flex items-center justify-between p-3 rounded-lg bg-zinc-700/50"
              >
                <div>
                  <div class="font-mono text-sm">{tool["name"]}</div>
                  <div class="text-xs text-zinc-400">{tool["description"]}</div>
                </div>
                <label class="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    class="sr-only peer"
                    checked={tool_enabled?(@tool_configs, @selected_server.id, tool["name"])}
                    phx-click="toggle_tool"
                    phx-value-server-id={@selected_server.id}
                    phx-value-tool-name={tool["name"]}
                  />
                  <div class="w-11 h-6 bg-zinc-600 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600">
                  </div>
                </label>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.modal
        :if={@show_add_server_modal}
        id="add-server-modal"
        show
        on_cancel={JS.push("hide_add_server")}
      >
        <.header>
          Add MCP Server
        </.header>

        <.simple_form for={@server_form} phx-submit="create_server" phx-change="validate_server">
          <.input field={@server_form[:name]} label="Name" required />
          <.input field={@server_form[:description]} label="Description" type="textarea" />
          <.input
            field={@server_form[:transport_type]}
            label="Transport Type"
            type="select"
            options={[{"STDIO (Local)", "stdio"}, {"HTTP (Remote)", "http"}]}
            required
          />

          <div :if={@server_form[:transport_type].value == "stdio"}>
            <.input
              field={@server_form[:command]}
              label="Command"
              placeholder="npx mcp-server-..."
              required
            />
            <p class="text-xs text-zinc-500 mt-1">
              The command to run the MCP server (e.g., npx, uvx, or a path to an executable)
            </p>
          </div>

          <div :if={@server_form[:transport_type].value == "http"}>
            <.input
              field={@server_form[:base_url]}
              label="Base URL"
              placeholder="http://localhost:4000"
              required
            />
          </div>

          <:actions>
            <.button type="button" phx-click="hide_add_server" class="bg-zinc-700 hover:bg-zinc-600">
              Cancel
            </.button>
            <.button type="submit" phx-disable-with="Creating...">
              Create Server
            </.button>
          </:actions>
        </.simple_form>
      </.modal>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("show_add_server", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_server_modal, true)
     |> assign(
       :server_form,
       to_form(build_server_changeset(%{"transport_type" => "stdio"}), as: :server)
     )}
  end

  def handle_event("hide_add_server", _params, socket) do
    {:noreply, assign(socket, :show_add_server_modal, false)}
  end

  def handle_event("validate_server", %{"server" => params}, socket) do
    changeset = build_server_changeset(params)
    {:noreply, assign(socket, :server_form, to_form(changeset, as: :server, action: :validate))}
  end

  def handle_event("create_server", %{"server" => params}, socket) do
    user_id = socket.assigns.current_user.id

    case MCP.create_user_server(user_id, params) do
      {:ok, server} ->
        servers = MCP.list_servers_for_user(user_id)
        user_servers = MCP.list_user_servers(user_id)

        {:noreply,
         socket
         |> assign(:servers, servers)
         |> assign(:user_servers, user_servers)
         |> assign(:show_add_server_modal, false)
         |> assign(:selected_server, server)
         |> put_flash(:info, "Server created successfully")}

      {:error, changeset} ->
        {:noreply, assign(socket, :server_form, to_form(changeset, as: :server, action: :insert))}
    end
  end

  def handle_event("select_server", %{"id" => server_id}, socket) do
    server = MCP.get_server!(server_id)

    # Try to fetch tools from the server
    tools = fetch_server_tools(server)

    {:noreply,
     socket
     |> assign(:selected_server, server)
     |> assign(:server_tools, tools)}
  end

  def handle_event("delete_server", %{"id" => server_id}, socket) do
    server = MCP.get_server!(server_id)
    user_id = socket.assigns.current_user.id

    # Only allow deleting own servers
    if server.user_id == user_id do
      case MCP.delete_server(server) do
        {:ok, _deleted} ->
          servers = MCP.list_servers_for_user(user_id)
          user_servers = MCP.list_user_servers(user_id)

          selected =
            if socket.assigns.selected_server && socket.assigns.selected_server.id == server_id do
              nil
            else
              socket.assigns.selected_server
            end

          {:noreply,
           socket
           |> assign(:servers, servers)
           |> assign(:user_servers, user_servers)
           |> assign(:selected_server, selected)
           |> assign(:server_tools, if(selected, do: socket.assigns.server_tools, else: []))
           |> put_flash(:info, "Server deleted")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to delete server")}
      end
    else
      {:noreply, put_flash(socket, :error, "Cannot delete this server")}
    end
  end

  def handle_event("toggle_tool", %{"server-id" => server_id, "tool-name" => tool_name}, socket) do
    user_id = socket.assigns.current_user.id

    # Check current state and toggle
    if MCP.tool_enabled?(user_id, server_id, tool_name) do
      MCP.disable_tool(user_id, server_id, tool_name)
    else
      MCP.enable_tool(user_id, server_id, tool_name)
    end

    # Reload tool configs
    tool_configs = MCP.list_user_tool_configs(user_id)
    {:noreply, assign(socket, :tool_configs, tool_configs)}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_server_changeset(params) do
    Server.changeset(%Server{}, params)
  end

  # TODO: Implement tool fetching from MCP servers
  # Currently returns empty list because:
  # 1. Tools require an active connection to the MCP server
  # 2. The server process is managed by ClientRegistry and may not be running
  # 3. Future implementation should:
  #    - Call ClientRegistry.get_client/1 to ensure server is connected
  #    - Use ToolRegistry.get_server_tools/1 to fetch available tools
  #    - Handle connection errors gracefully in the UI
  defp fetch_server_tools(_server) do
    []
  end

  defp tool_enabled?(tool_configs, server_id, tool_name) do
    case Enum.find(tool_configs, fn c ->
           c.mcp_server_id == server_id && c.tool_name == tool_name
         end) do
      nil -> true
      config -> config.enabled
    end
  end
end
