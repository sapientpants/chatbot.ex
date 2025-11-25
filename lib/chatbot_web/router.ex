defmodule ChatbotWeb.Router do
  @moduledoc """
  Application router defining all HTTP routes and pipelines.

  Configures authentication routes, chat interface, and development tools.
  """
  use ChatbotWeb, :router

  import ChatbotWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChatbotWeb.Layouts, :root}
    plug :protect_from_forgery

    # Content Security Policy and security headers configuration
    # Note: 'unsafe-inline' and 'unsafe-eval' are required for Phoenix LiveView to function properly:
    # - 'unsafe-inline' allows inline <script> tags that LiveView uses for client-server communication
    # - 'unsafe-eval' is needed for LiveView's JavaScript runtime
    # - 'ws: wss:' allows WebSocket connections for LiveView real-time updates
    # For production, consider using nonces or hashes with LiveView 0.18+ for stricter CSP
    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:; font-src 'self' data:; object-src 'none'; frame-ancestors 'none'",
      "x-frame-options" => "DENY",
      "x-content-type-options" => "nosniff",
      "referrer-policy" => "strict-origin-when-cross-origin",
      "permissions-policy" => "geolocation=(), microphone=(), camera=()"
    }

    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ChatbotWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Authentication routes
  scope "/", ChatbotWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{ChatbotWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/register", RegistrationLive
      live "/login", LoginLive
      live "/forgot-password", ForgotPasswordLive
      live "/reset-password/:token", ResetPasswordLive
    end

    post "/login", UserSessionController, :create
  end

  # Authenticated routes
  scope "/", ChatbotWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ChatbotWeb.UserAuth, :ensure_authenticated}] do
      live "/chat", ChatLive.Index
      live "/chat/:id", ChatLive.Show
    end

    delete "/logout", UserSessionController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", ChatbotWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:chatbot, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ChatbotWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
