defmodule ChatbotWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plugs to prevent abuse and protect application resources.

  Configuration is loaded from application config under `:chatbot, :rate_limits`.
  """
  import Plug.Conn
  import Phoenix.Controller

  @type rate_limit_result :: :ok | {:error, String.t()}

  @doc """
  Plug callback for initialization.
  """
  @spec init(atom() | keyword()) :: atom() | keyword()
  def init(opts), do: opts

  @doc """
  Plug callback that routes to the appropriate rate limiter based on action.
  """
  @spec call(Plug.Conn.t(), atom()) :: Plug.Conn.t()
  def call(conn, action) when is_atom(action) do
    apply(__MODULE__, action, [conn, []])
  end

  @doc """
  Rate limits login attempts per IP address.
  Configured via `:chatbot, :rate_limits, :login`.
  """
  @spec rate_limit_login(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def rate_limit_login(conn, _opts) do
    key = "login:#{get_ip(conn)}"
    config = get_rate_limit_config(:login)

    case Hammer.check_rate(key, config[:window_ms], config[:max_attempts]) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_flash(:error, "Too many login attempts. Please try again in a minute.")
        |> redirect(to: "/login")
        |> halt()
    end
  end

  @doc """
  Rate limits registration attempts per IP address.
  Configured via `:chatbot, :rate_limits, :registration`.
  """
  @spec rate_limit_registration(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def rate_limit_registration(conn, _opts) do
    key = "registration:#{get_ip(conn)}"
    config = get_rate_limit_config(:registration)

    case Hammer.check_rate(key, config[:window_ms], config[:max_attempts]) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_flash(:error, "Too many registration attempts. Please try again later.")
        |> redirect(to: "/register")
        |> halt()
    end
  end

  @doc """
  Rate limits message creation per user with burst protection.
  Can be called from LiveView.
  Implements two-tier rate limiting configured via `:chatbot, :rate_limits`.
  """
  @spec check_message_rate_limit(integer() | String.t()) :: rate_limit_result()
  def check_message_rate_limit(user_id) do
    key = "messages:#{user_id}"
    burst_key = "messages_burst:#{user_id}"
    msg_config = get_rate_limit_config(:messages)
    burst_config = get_rate_limit_config(:messages_burst)

    with {:allow, _count} <-
           Hammer.check_rate(key, msg_config[:window_ms], msg_config[:max_attempts]),
         {:allow, _count} <-
           Hammer.check_rate(burst_key, burst_config[:window_ms], burst_config[:max_attempts]) do
      :ok
    else
      {:deny, _limit} -> {:error, "Rate limit exceeded. Please slow down."}
    end
  end

  @doc """
  Rate limits registration attempts per IP.
  Can be called from LiveView.
  Configured via `:chatbot, :rate_limits, :registration`.
  """
  @spec check_registration_rate_limit(String.t()) :: rate_limit_result()
  def check_registration_rate_limit(ip) do
    key = "registration:#{ip}"
    config = get_rate_limit_config(:registration)

    case Hammer.check_rate(key, config[:window_ms], config[:max_attempts]) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, "Too many registration attempts. Please try again later."}
    end
  end

  @doc """
  Rate limits password reset requests per email.
  Can be called from LiveView.
  Configured via `:chatbot, :rate_limits, :password_reset`.
  """
  @spec check_password_reset_rate_limit(String.t()) :: rate_limit_result()
  def check_password_reset_rate_limit(email) do
    key = "password_reset:#{String.downcase(email)}"
    config = get_rate_limit_config(:password_reset)

    case Hammer.check_rate(key, config[:window_ms], config[:max_attempts]) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, "Too many password reset requests. Please try again later."}
    end
  end

  defp get_rate_limit_config(key) do
    Application.get_env(:chatbot, :rate_limits, [])[key] || default_config(key)
  end

  defp default_config(:login), do: [window_ms: 60_000, max_attempts: 5]
  defp default_config(:registration), do: [window_ms: 3_600_000, max_attempts: 3]
  defp default_config(:password_reset), do: [window_ms: 3_600_000, max_attempts: 3]
  defp default_config(:messages), do: [window_ms: 60_000, max_attempts: 10]
  defp default_config(:messages_burst), do: [window_ms: 10_000, max_attempts: 3]

  @doc """
  Extracts the client IP address from the connection.
  Handles X-Forwarded-For headers for requests behind proxies/load balancers.
  """
  @spec get_ip(Plug.Conn.t()) :: String.t()
  def get_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _rest] ->
        # X-Forwarded-For can contain multiple IPs: "client, proxy1, proxy2"
        # The first IP is the original client
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        conn.remote_ip
        |> Tuple.to_list()
        |> Enum.join(".")
    end
  end
end
