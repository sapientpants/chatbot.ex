defmodule Chatbot.MCP.ClientRegistry do
  @moduledoc """
  GenServer that manages MCP client connections.

  - Lazily initializes MCP clients when first needed
  - Maintains ETS cache of client PIDs and status
  - Implements circuit breaker protection per server
  - Cleans up disconnected clients
  """

  use GenServer
  require Logger

  @ets_table :mcp_clients
  @fuse_name :mcp_client_fuse
  @fuse_opts {{:standard, 3, 30_000}, {:reset, 15_000}}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the ClientRegistry.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets or creates an MCP client for the given server.
  Returns `{:ok, client_pid}` or `{:error, reason}`.
  """
  @spec get_client(Chatbot.MCP.Server.t()) :: {:ok, pid()} | {:error, term()}
  def get_client(%Chatbot.MCP.Server{} = server) do
    case check_circuit_breaker(server.id) do
      :ok ->
        case lookup_client(server.id) do
          {:ok, pid} when is_pid(pid) ->
            if Process.alive?(pid), do: {:ok, pid}, else: start_client(server)

          :not_found ->
            start_client(server)
        end

      {:error, :circuit_open} = error ->
        error
    end
  end

  @doc """
  Stops an MCP client for the given server.
  """
  @spec stop_client(binary()) :: :ok
  def stop_client(server_id) do
    GenServer.call(__MODULE__, {:stop_client, server_id})
  end

  @doc """
  Lists all active clients.
  """
  @spec list_clients() :: [{binary(), pid(), atom()}]
  def list_clients do
    :ets.tab2list(@ets_table)
  end

  @doc """
  Records a failure for circuit breaker.
  """
  @spec record_failure(binary()) :: :ok
  def record_failure(server_id) do
    :fuse.melt(fuse_name(server_id))
    :ok
  end

  @doc """
  Records a success for circuit breaker.
  """
  @spec record_success(binary()) :: :ok
  def record_success(server_id) do
    :fuse.reset(fuse_name(server_id))
    :ok
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(_opts) do
    # Create ETS table for client lookup
    :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true])

    {:ok, %{monitors: %{}}}
  end

  @impl GenServer
  def handle_call({:start_client, server}, _from, state) do
    case do_start_client(server, state) do
      {:ok, pid, new_state} ->
        {:reply, {:ok, pid}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:stop_client, server_id}, _from, state) do
    case :ets.lookup(@ets_table, server_id) do
      [{^server_id, pid, _status}] ->
        # Stop the client process
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5000)
        :ets.delete(@ets_table, server_id)
        new_monitors = Map.delete(state.monitors, server_id)
        {:reply, :ok, %{state | monitors: new_monitors}}

      [] ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Find which server this monitor belongs to
    case Enum.find(state.monitors, fn {_id, mon_ref} -> mon_ref == ref end) do
      {server_id, _ref} ->
        Logger.warning("MCP client for server #{server_id} went down: #{inspect(reason)}")
        :ets.delete(@ets_table, server_id)
        new_monitors = Map.delete(state.monitors, server_id)
        {:noreply, %{state | monitors: new_monitors}}

      nil ->
        {:noreply, state}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp start_client(server) do
    GenServer.call(__MODULE__, {:start_client, server})
  end

  defp do_start_client(server, state) do
    # Install fuse if not already done
    install_fuse(server.id)

    # Build transport config based on server type
    transport_config = build_transport_config(server)

    # Create a unique module name for this client
    client_module = client_module_name(server.id)

    # Define the client module dynamically
    define_client_module(client_module)

    # Start the client process
    case start_client_process(client_module, transport_config) do
      {:ok, pid} ->
        # Monitor the client process
        ref = Process.monitor(pid)

        # Store in ETS
        :ets.insert(@ets_table, {server.id, pid, :connected})

        Logger.info("Started MCP client for server #{server.name} (#{server.id})")

        {:ok, pid, %{state | monitors: Map.put(state.monitors, server.id, ref)}}

      {:error, reason} = error ->
        Logger.error("Failed to start MCP client for #{server.name}: #{inspect(reason)}")
        record_failure(server.id)
        error
    end
  end

  defp build_transport_config(%{transport_type: "stdio"} = server) do
    {:stdio,
     command: server.command, args: server.args || [], env: Map.to_list(server.env || %{})}
  end

  defp build_transport_config(%{transport_type: "http"} = server) do
    {:streamable_http, base_url: server.base_url, headers: Map.to_list(server.headers || %{})}
  end

  defp client_module_name(server_id) do
    # Create a unique atom for this server's client module
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat([Chatbot.MCP.Client, "Server_#{String.replace(server_id, "-", "_")}"])
  end

  defp define_client_module(module_name) do
    # Only define if not already defined
    unless Code.ensure_loaded?(module_name) do
      Module.create(
        module_name,
        quote do
          use Anubis.Client,
            name: "Chatbot",
            version: "1.0.0",
            protocol_version: "2025-03-26"
        end,
        Macro.Env.location(__ENV__)
      )
    end

    module_name
  end

  # Start the client under a DynamicSupervisor
  # credo:disable-for-next-line Credo.Check.Readability.PreferImplicitTry
  defp start_client_process(client_module, transport_config) do
    child_spec = {client_module, [transport: transport_config]}

    case DynamicSupervisor.start_child(Chatbot.MCP.ClientSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp lookup_client(server_id) do
    case :ets.lookup(@ets_table, server_id) do
      [{^server_id, pid, _status}] -> {:ok, pid}
      [] -> :not_found
    end
  end

  defp check_circuit_breaker(server_id) do
    fuse = fuse_name(server_id)
    install_fuse(server_id)

    case :fuse.ask(fuse, :sync) do
      :ok -> :ok
      :blown -> {:error, :circuit_open}
    end
  end

  defp install_fuse(server_id) do
    fuse = fuse_name(server_id)

    case :fuse.ask(fuse, :sync) do
      {:error, :not_found} ->
        :fuse.install(fuse, @fuse_opts)

      _already_installed ->
        :ok
    end
  end

  defp fuse_name(server_id), do: {@fuse_name, server_id}
end
