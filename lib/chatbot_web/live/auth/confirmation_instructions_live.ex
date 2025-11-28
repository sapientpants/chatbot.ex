defmodule ChatbotWeb.ConfirmationInstructionsLive do
  @moduledoc """
  LiveView for requesting new confirmation instructions.

  Allows users to request a new confirmation email if their original link expired.
  """
  use ChatbotWeb, :live_view

  alias Chatbot.Accounts

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <ChatbotWeb.Layouts.navbar current_user={assigns[:current_user]} />

      <div class="mx-auto max-w-sm mt-10">
        <h1 class="text-2xl font-bold text-center mb-2">Resend Confirmation Instructions</h1>
        <p class="text-center text-sm text-base-content/70 mb-6">
          Enter your email address and we'll send you a new confirmation link.
        </p>

        <.form
          for={@form}
          id="resend_confirmation_form"
          phx-submit="send"
          class="space-y-4"
        >
          <.input field={@form[:email]} type="email" label="Email" required />

          <.button variant="primary" phx-disable-with="Sending..." class="w-full">
            Resend confirmation instructions
          </.button>
        </.form>

        <p class="text-center text-sm mt-6">
          <.link navigate={~p"/login"} class="font-semibold text-primary hover:underline">
            Back to login
          </.link>
        </p>
      </div>
    </div>
    """
  end

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{"email" => ""}, as: "user"))}
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("send", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/confirm/#{&1}")
      )
    end

    # Always show success message to prevent email enumeration
    {:noreply,
     socket
     |> put_flash(
       :info,
       "If your email is in our system and has not been confirmed yet, you will receive an email with instructions shortly."
     )
     |> push_navigate(to: ~p"/login")}
  end
end
