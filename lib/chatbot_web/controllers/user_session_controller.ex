defmodule ChatbotWeb.UserSessionController do
  @moduledoc """
  Handles user session creation and deletion (login/logout).

  Rate-limited to prevent brute force attacks.
  """
  use ChatbotWeb, :controller

  alias Chatbot.Accounts
  alias ChatbotWeb.UserAuth

  plug ChatbotWeb.Plugs.RateLimiter, :rate_limit_login when action == :create

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.get_user_by_email_and_password(email, password) do
      %{confirmed_at: nil} = _user ->
        # User exists but hasn't confirmed their email
        conn
        |> put_flash(
          :error,
          "Please confirm your email before logging in. " <>
            "Check your inbox or request a new confirmation link."
        )
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/login")

      %{} = user ->
        # User is confirmed, proceed with login
        UserAuth.log_in_user(conn, user, user_params)

      nil ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/login")
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
