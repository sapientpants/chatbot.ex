defmodule ChatbotWeb.RegistrationLive do
  @moduledoc """
  LiveView for user registration.

  Handles user signup with email and password, with rate limiting to prevent abuse.
  """
  use ChatbotWeb, :live_view

  alias Chatbot.Accounts
  alias Chatbot.Accounts.User
  alias ChatbotWeb.Plugs.RateLimiter

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm mt-10">
      <h1 class="text-2xl font-bold text-center mb-2">Register for an account</h1>
      <p class="text-center text-sm mb-6">
        Already registered?
        <.link navigate={~p"/login"} class="font-semibold text-blue-600 hover:underline">
          Log in
        </.link>
        to your account now.
      </p>

      <.form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        class="space-y-4"
      >
        <div :if={@check_errors} class="alert alert-error mb-4">
          <p>Oops, something went wrong! Please check the errors below.</p>
        </div>

        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <.button phx-disable-with="Creating account..." class="w-full">Create an account</.button>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    ip =
      case get_connect_info(socket, :peer_data) do
        %{address: address} -> address |> Tuple.to_list() |> Enum.join(".")
        _ -> "unknown"
      end

    case RateLimiter.check_registration_rate_limit(ip) do
      :ok ->
        case Accounts.register_user(user_params) do
          {:ok, _user} ->
            {:noreply,
             socket
             |> put_flash(:info, "Account created successfully!")
             |> redirect(to: ~p"/login")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
        end

      {:error, message} ->
        {:noreply,
         socket
         |> put_flash(:error, message)
         |> push_navigate(to: ~p"/register")}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
