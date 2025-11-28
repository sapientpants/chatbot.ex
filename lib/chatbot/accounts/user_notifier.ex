defmodule Chatbot.Accounts.UserNotifier do
  @moduledoc """
  Notification functions for user-related emails.

  In development, emails are logged to the console.
  In production, you would use Swoosh or another email library.
  """

  require Logger

  @doc """
  Delivers email confirmation instructions to the given user.

  ## Examples

      iex> deliver_confirmation_instructions(user, "http://example.com/confirm/token")
      {:ok, %{to: user.email, body: "..."}}

  """
  @spec deliver_confirmation_instructions(Chatbot.Accounts.User.t(), String.t()) :: {:ok, map()}
  def deliver_confirmation_instructions(user, url) do
    Logger.info("""
    ==============================
    Email Confirmation Instructions
    ==============================
    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this message.

    This link will expire in 7 days.
    ==============================
    """)

    {:ok, %{to: user.email, body: "Confirmation instructions sent"}}
  end

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
    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this message.

    This link will expire in 1 day.
    ==============================
    """)

    {:ok, %{to: user.email, body: "Password reset instructions sent"}}
  end
end
