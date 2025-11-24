defmodule Chatbot.Mailer do
  @moduledoc """
  Email delivery module using Swoosh.

  Configured to send transactional emails for the application.
  """
  use Swoosh.Mailer, otp_app: :chatbot
end
