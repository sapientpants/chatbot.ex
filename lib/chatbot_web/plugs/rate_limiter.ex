defmodule ChatbotWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plugs to prevent abuse and protect application resources.

  Configuration is loaded from application config under `:chatbot, :rate_limits`.
  """
  import Plug.Conn
  import Phoenix.Controller
  import Bitwise

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

  Security considerations:
  - X-Forwarded-For headers can be spoofed by clients
  - Only trust forwarded headers if behind a known proxy (configured via :trusted_proxies)
  - Validates IP format to prevent injection attacks
  - Falls back to remote_ip if header is untrusted or invalid
  """
  @spec get_ip(Plug.Conn.t()) :: String.t()
  def get_ip(conn) do
    remote_ip = format_ip(conn.remote_ip)

    # Only trust X-Forwarded-For if request comes from a trusted proxy
    if trusted_proxy?(conn.remote_ip) do
      case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
        [forwarded | _rest] ->
          first_valid_ip =
            forwarded
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.find(&valid_ip?/1)

          first_valid_ip || remote_ip

        [] ->
          remote_ip
      end
    else
      remote_ip
    end
  end

  # Formats an IP tuple to a string
  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip({a, b, c, d, e, f, g, h}), do: "#{a}:#{b}:#{c}:#{d}:#{e}:#{f}:#{g}:#{h}"
  defp format_ip(_other), do: "unknown"

  # Validates IP address format (IPv4 or IPv6)
  defp valid_ip?(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, _addr} -> true
      {:error, _reason} -> false
    end
  end

  defp valid_ip?(_other), do: false

  # Checks if the remote IP is in the trusted proxy list
  defp trusted_proxy?(remote_ip) do
    trusted_proxies = get_trusted_proxies()

    Enum.any?(trusted_proxies, fn proxy ->
      ip_in_range?(remote_ip, proxy)
    end)
  end

  # Gets configured trusted proxy networks
  defp get_trusted_proxies do
    Application.get_env(:chatbot, :rate_limits, [])[:trusted_proxies] ||
      [
        # Loopback (localhost)
        {{127, 0, 0, 0}, 8},
        # Private networks (common for reverse proxies)
        {{10, 0, 0, 0}, 8},
        {{172, 16, 0, 0}, 12},
        {{192, 168, 0, 0}, 16}
      ]
  end

  # Checks if an IP is within a CIDR range
  defp ip_in_range?({a, b, c, d}, {{na, nb, nc, nd}, prefix}) do
    ip_int = a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d
    network_int = na <<< 24 ||| nb <<< 16 ||| nc <<< 8 ||| nd
    mask = 0xFFFFFFFF <<< (32 - prefix) &&& 0xFFFFFFFF
    (ip_int &&& mask) == (network_int &&& mask)
  end

  defp ip_in_range?(_ip, _network), do: false
end
