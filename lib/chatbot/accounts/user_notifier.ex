defmodule Chatbot.Accounts.UserNotifier do
  @moduledoc """
  Notification functions for user-related emails.

  For this single-user local app, notifications are logged to the console.
  """

  alias Chatbot.PII

  require Logger

  @doc """
  Delivers password reset instructions to the given user.

  ## Examples

      iex> deliver_reset_password_instructions(user, "http://example.com/reset/token")
      {:ok, %{to: user.email, body: "..."}}

  """
  @spec deliver_reset_password_instructions(Chatbot.Accounts.User.t(), String.t()) :: {:ok, map()}
  def deliver_reset_password_instructions(user, url) do
    Logger.info("""
    ==============================
    Password Reset Instructions
    ==============================
    Hi #{PII.mask_email(user.email)},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this message.

    This link will expire in 1 day.
    ==============================
    """)

    {:ok, %{to: user.email, body: "Password reset instructions sent"}}
  end
end
