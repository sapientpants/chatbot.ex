defmodule ChatbotWeb.ForgotPasswordLive do
  @moduledoc """
  LiveView for requesting a password reset.

  Allows users to enter their email address to receive password reset instructions.
  """
  use ChatbotWeb, :live_view

  alias Chatbot.Accounts

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <ChatbotWeb.Layouts.navbar current_user={assigns[:current_user]} />

      <div class="mx-auto max-w-sm mt-10">
        <h1 class="text-2xl font-bold text-center mb-2">Forgot your password?</h1>
        <p class="text-center text-sm mb-6 text-base-content/70">
          We'll send you a link to reset your password.
        </p>

        <.form for={@form} id="forgot_password_form" phx-submit="send_reset_link" class="space-y-4">
          <.input field={@form[:email]} type="email" label="Email" required />

          <.button phx-disable-with="Sending..." class="w-full">
            Send reset link
          </.button>
        </.form>

        <div class="text-center mt-6">
          <.link navigate={~p"/login"} class="text-sm text-blue-600 hover:underline">
            Back to log in
          </.link>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{"email" => ""}, as: "user"))}
  end

  def handle_event("send_reset_link", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/reset-password/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly. Please check your console for the reset link (email not configured)."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/login")}
  end
end
