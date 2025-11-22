defmodule ChatbotWeb.LoginLive do
  use ChatbotWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm mt-10">
      <h1 class="text-2xl font-bold text-center mb-2">Log in to account</h1>
      <p class="text-center text-sm mb-6">
        Don't have an account?
        <.link navigate={~p"/register"} class="font-semibold text-blue-600 hover:underline">
          Sign up
        </.link>
        for an account now.
      </p>

      <.form for={@form} id="login_form" action={~p"/login"} phx-update="ignore" class="space-y-4">
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />

        <.button phx-disable-with="Logging in..." class="w-full">
          Log in <span aria-hidden="true">→</span>
        </.button>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
