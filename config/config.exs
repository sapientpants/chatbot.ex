# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :chatbot,
  ecto_repos: [Chatbot.Repo],
  generators: [timestamp_type: :utc_datetime]

# Rate limiting configuration
config :chatbot, :rate_limits,
  login: [window_ms: 60_000, max_attempts: 5],
  registration: [window_ms: 3_600_000, max_attempts: 3],
  password_reset: [window_ms: 3_600_000, max_attempts: 3],
  messages: [window_ms: 60_000, max_attempts: 10],
  messages_burst: [window_ms: 10_000, max_attempts: 3]

# LM Studio API configuration
config :chatbot, :lm_studio,
  base_url: "http://localhost:1234/v1",
  stream_timeout_ms: 300_000

# Model cache configuration
config :chatbot, :model_cache, ttl_ms: 60_000

# Ollama configuration (for embeddings and chat completions)
config :chatbot, :ollama,
  base_url: "http://localhost:11434",
  embedding_model: "qwen3-embedding:0.6b",
  embedding_dimension: 1024,
  timeout_ms: 30_000,
  stream_timeout_ms: 300_000

# MCP (Model Context Protocol) configuration
config :chatbot, :mcp,
  tool_timeout_ms: 30_000,
  agent_loop_timeout_ms: 120_000,
  max_agent_iterations: 10,
  max_result_size_bytes: 100_000

# Memory system configuration
config :chatbot, :memory,
  enabled: true,
  max_memories_per_user: 1000,
  retrieval_limit: 5,
  semantic_weight: 0.6,
  keyword_weight: 0.4,
  token_budget: 4000,
  fact_extraction_enabled: true,
  summarization_threshold: 30

# UI configuration
config :chatbot, :ui,
  max_model_name_length: 20,
  max_textarea_height_px: 200

# Configures the endpoint
config :chatbot, ChatbotWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ChatbotWeb.ErrorHTML, json: ChatbotWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Chatbot.PubSub,
  live_view: [signing_salt: "UTkFdypX"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :chatbot, Chatbot.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
# Uses code splitting to lazy-load highlight.js and reduce initial bundle size
config :esbuild,
  version: "0.25.4",
  chatbot: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --splitting --format=esm --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  chatbot: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
