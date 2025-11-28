defmodule ChatbotWeb.ConfirmationLive do
  @moduledoc """
  LiveView for email confirmation.

  Confirms a user's email when they click the confirmation link.
  """
  use ChatbotWeb, :live_view

  alias Chatbot.Accounts

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <ChatbotWeb.Layouts.navbar current_user={assigns[:current_user]} />

      <div class="mx-auto max-w-sm mt-10">
        <h1 class="text-2xl font-bold text-center mb-2">Confirm Your Account</h1>

        <div :if={@status == :loading} class="text-center py-8">
          <span class="loading loading-spinner loading-lg"></span>
          <p class="mt-4 text-base-content/70">Confirming your account...</p>
        </div>

        <div :if={@status == :success} class="text-center py-8">
          <div class="text-success text-6xl mb-4">✓</div>
          <p class="text-lg font-medium mb-4">Your account has been confirmed!</p>
          <.link navigate={~p"/login"} class="btn btn-primary">
            Log in to your account
          </.link>
        </div>

        <div :if={@status == :error} class="text-center py-8">
          <div class="text-error text-6xl mb-4">✗</div>
          <p class="text-lg font-medium mb-2">Confirmation link is invalid or expired.</p>
          <p class="text-base-content/70 mb-4">
            The link may have already been used or has expired after 7 days.
          </p>
          <.link navigate={~p"/confirm/resend"} class="btn btn-primary">
            Request a new confirmation link
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"token" => token}, _session, socket) do
    if connected?(socket) do
      # Process confirmation when LiveView is connected
      case Accounts.confirm_user(token) do
        {:ok, _user} ->
          {:ok, assign(socket, status: :success)}

        :error ->
          {:ok, assign(socket, status: :error)}
      end
    else
      # Initial render - show loading state
      {:ok, assign(socket, status: :loading)}
    end
  end
end
