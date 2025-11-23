defmodule ChatbotWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plugs to prevent abuse and protect application resources.
  """
  import Plug.Conn
  import Phoenix.Controller

  @doc """
  Plug callback for initialization.
  """
  def init(opts), do: opts

  @doc """
  Plug callback that routes to the appropriate rate limiter based on action.
  """
  def call(conn, action) when is_atom(action) do
    apply(__MODULE__, action, [conn, []])
  end

  @doc """
  Rate limits login attempts to 5 per minute per IP address.
  """
  def rate_limit_login(conn, _opts) do
    key = "login:#{get_ip(conn)}"

    case Hammer.check_rate(key, 60_000, 5) do
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
  Rate limits registration attempts to 3 per hour per IP address.
  """
  def rate_limit_registration(conn, _opts) do
    key = "registration:#{get_ip(conn)}"

    case Hammer.check_rate(key, 60_000 * 60, 3) do
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
  Rate limits message creation to 30 per minute per user.
  Can be called from LiveView with socket.
  """
  def check_message_rate_limit(user_id) do
    key = "messages:#{user_id}"

    case Hammer.check_rate(key, 60_000, 30) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, "Rate limit exceeded. Please slow down."}
    end
  end

  defp get_ip(conn) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end
end
