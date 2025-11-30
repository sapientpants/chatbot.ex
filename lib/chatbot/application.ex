defmodule Chatbot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      ChatbotWeb.Telemetry,
      Chatbot.Repo,
      {DNSCluster, query: Application.get_env(:chatbot, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Chatbot.PubSub},
      # Rate limiting backend
      {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]},
      # System settings (must start before ModelCache)
      Chatbot.Settings,
      # Model list cache
      Chatbot.ModelCache,
      # Embedding cache for memory search queries
      Chatbot.Memory.EmbeddingCache,
      # Task supervisor for background tasks
      {Task.Supervisor, name: Chatbot.TaskSupervisor},
      # MCP client infrastructure
      {DynamicSupervisor, name: Chatbot.MCP.ClientSupervisor, strategy: :one_for_one},
      Chatbot.MCP.ClientRegistry,
      # Start to serve requests, typically the last entry
      ChatbotWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chatbot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl Application
  def config_change(changed, _new, removed) do
    ChatbotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
