defmodule ChatbotWeb.ResetPasswordLive do
  @moduledoc """
  LiveView for resetting a user's password.

  Validates the reset token and allows the user to set a new password.
  """
  use ChatbotWeb, :live_view

  alias Chatbot.Accounts

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <ChatbotWeb.Layouts.navbar current_user={assigns[:current_user]} />

      <div class="mx-auto max-w-sm mt-10">
        <h1 class="text-2xl font-bold text-center mb-2">Reset password</h1>
        <p class="text-center text-sm mb-6 text-base-content/70">
          Enter your new password below.
        </p>

        <.form
          for={@form}
          id="reset_password_form"
          phx-submit="reset_password"
          phx-change="validate"
          class="space-y-4"
        >
          <.input
            field={@form[:password]}
            type="password"
            label="New password"
            required
            autocomplete="new-password"
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            required
            autocomplete="new-password"
          />

          <.button variant="primary" phx-disable-with="Resetting..." class="w-full">
            Reset password
          </.button>
        </.form>

        <div class="text-center mt-6">
          <.link navigate={~p"/login"} class="text-sm text-primary hover:underline">
            Back to log in
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t(), keyword()}
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.get_user_by_reset_password_token(token) do
        %Accounts.User{} = user ->
          socket
          |> assign(:user, user)
          |> assign(:token, token)
          |> assign(:valid_token, true)
          |> assign_form(Accounts.change_user_password(user))

        nil ->
          socket
          |> assign(:user, nil)
          |> assign(:token, nil)
          |> assign(:valid_token, false)
          |> put_flash(:error, "Reset password link is invalid or it has expired.")
          |> redirect(to: ~p"/forgot-password")
      end

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
