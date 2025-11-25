defmodule ChatbotWeb.LoginLive do
  @moduledoc """
  LiveView for user login.

  Renders the login form and redirects to the session controller for authentication.
  """
  use ChatbotWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <ChatbotWeb.Layouts.navbar current_user={assigns[:current_user]} />

      <div class="flex items-center justify-center px-4 py-12 sm:px-6 lg:px-8">
        <div class="w-full max-w-md">
          <div class="bg-base-100 shadow-xl rounded-2xl p-8">
            <h1 class="text-3xl font-bold text-center mb-2">Log in to account</h1>
            <p class="text-center text-sm text-base-content/70 mb-8">
              Don't have an account?
              <.link
                navigate={~p"/register"}
                class="font-semibold text-primary hover:text-primary-focus hover:underline"
              >
                Sign up
              </.link>
              for an account now.
            </p>

            <.form
              for={@form}
              id="login_form"
              action={~p"/login"}
              phx-update="ignore"
              class="space-y-5"
            >
              <.input field={@form[:email]} type="email" label="Email" required />
              <.input field={@form[:password]} type="password" label="Password" required />

              <div class="flex items-center justify-between pt-1">
                <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
                <.link
                  navigate={~p"/forgot-password"}
                  class="text-sm text-primary hover:text-primary-focus hover:underline"
                >
                  Forgot password?
                </.link>
              </div>

              <div class="pt-2">
                <.button phx-disable-with="Logging in..." class="w-full btn-lg">
                  Log in
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
