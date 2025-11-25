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
    <div class="min-h-screen bg-base-200">
      <ChatbotWeb.Layouts.navbar current_user={assigns[:current_user]} />

      <div class="mx-auto max-w-sm mt-10">
        <h1 class="text-2xl font-bold text-center mb-2">Register for an account</h1>
        <p class="text-center text-sm mb-6">
          Already registered?
          <.link navigate={~p"/login"} class="font-semibold text-primary hover:underline">
            Log in
          </.link>
          to your account now.
        </p>

        <.form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          novalidate
          class="space-y-4"
        >
          <div :if={@check_errors} class="alert alert-error mb-4">
            <p>Oops, something went wrong! Please check the errors below.</p>
          </div>

          <.input field={@form[:email]} type="email" label="Email" required />

          <div class="form-control">
            <label class="label">
              <span class="label-text">Password</span>
            </label>
            <div class="relative">
              <input
                type={if @show_password, do: "text", else: "password"}
                name={@form[:password].name}
                id={@form[:password].id}
                value={Phoenix.HTML.Form.normalize_value("password", @form[:password].value)}
                class="input input-bordered w-full pr-10"
                required
              />
              <button
                type="button"
                phx-click="toggle_password"
                class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-700"
                aria-label={if @show_password, do: "Hide password", else: "Show password"}
              >
                <span :if={@show_password}>
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-5 h-5"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88"
                    />
                  </svg>
                </span>
                <span :if={!@show_password}>
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-5 h-5"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z"
                    />
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                    />
                  </svg>
                </span>
              </button>
            </div>
            <div :for={error <- @form[:password].errors} class="text-sm text-error mt-1">
              {translate_error(error)}
            </div>

            <div class="mt-2 p-3 bg-base-200 rounded-lg text-sm">
              <p class="font-medium mb-2">Password requirements:</p>
              <ul class="space-y-1">
                <li class={[
                  "flex items-center gap-2",
                  password_requirement_met?(@form[:password].value, :length) && "text-success"
                ]}>
                  <span :if={password_requirement_met?(@form[:password].value, :length)}>✓</span>
                  <span :if={!password_requirement_met?(@form[:password].value, :length)}>○</span>
                  At least 12 characters
                </li>
                <li class={[
                  "flex items-center gap-2",
                  password_requirement_met?(@form[:password].value, :uppercase) && "text-success"
                ]}>
                  <span :if={password_requirement_met?(@form[:password].value, :uppercase)}>✓</span>
                  <span :if={!password_requirement_met?(@form[:password].value, :uppercase)}>○</span>
                  At least one uppercase letter
                </li>
                <li class={[
                  "flex items-center gap-2",
                  password_requirement_met?(@form[:password].value, :special) && "text-success"
                ]}>
                  <span :if={password_requirement_met?(@form[:password].value, :special)}>✓</span>
                  <span :if={!password_requirement_met?(@form[:password].value, :special)}>○</span>
                  At least one special character
                </li>
              </ul>
            </div>
          </div>

          <.button phx-disable-with="Creating account..." class="w-full">Create an account</.button>
        </.form>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    # Get IP address during mount when connect_info is available
    ip =
      case get_connect_info(socket, :peer_data) do
        %{address: address} -> address |> Tuple.to_list() |> Enum.join(".")
        _ -> "unknown"
      end

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false, client_ip: ip, show_password: false)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("toggle_password", _params, socket) do
    {:noreply, assign(socket, :show_password, !socket.assigns.show_password)}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    # Use IP address stored in assigns during mount
    ip = socket.assigns.client_ip

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

  # Helper function to check password requirements
  defp password_requirement_met?(nil, _requirement), do: false
  defp password_requirement_met?("", _requirement), do: false

  defp password_requirement_met?(password, :length) when is_binary(password) do
    String.length(password) >= 12
  end

  defp password_requirement_met?(password, :uppercase) when is_binary(password) do
    String.match?(password, ~r/[A-Z]/)
  end

  defp password_requirement_met?(password, :special) when is_binary(password) do
    String.match?(password, ~r/[^A-Za-z0-9]/)
  end

  defp password_requirement_met?(_password, _requirement), do: false
end
