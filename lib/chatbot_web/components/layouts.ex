defmodule ChatbotWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ChatbotWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders the global navigation header with authentication links.

  Shows different content based on whether a user is logged in:
  - When logged out: Shows "Log in" and "Sign up" links
  - When logged in: Shows user email and "Logout" link

  ## Examples

      <.navbar current_user={@current_user} />
  """
  attr :current_user, :map, default: nil, doc: "the currently logged in user, if any"

  def navbar(assigns) do
    ~H"""
    <!-- Skip to main content link for keyboard users -->
    <a
      href="#main-content"
      class="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:btn focus:btn-primary"
    >
      Skip to main content
    </a>

    <header
      role="banner"
      class="navbar bg-base-100 border-b border-base-300 px-4 sm:px-6 lg:px-8 shadow-sm"
    >
      <div class="flex-1">
        <.link
          navigate={~p"/"}
          class="flex items-center gap-2 text-xl font-bold hover:text-primary transition-colors"
          aria-label="Chatbot home"
        >
          Chatbot
        </.link>
      </div>
      <div class="flex-none">
        <nav aria-label="Main navigation">
          <ul class="menu menu-horizontal px-1 gap-2 items-center">
            <%= if @current_user do %>
              <li>
                <span class="text-sm px-3 py-2 rounded-lg bg-base-200">{@current_user.email}</span>
              </li>
              <li>
                <.link
                  href={~p"/logout"}
                  method="delete"
                  class="btn btn-sm btn-ghost hover:btn-error transition-colors"
                >
                  Logout
                </.link>
              </li>
            <% else %>
              <li>
                <.link
                  navigate={~p"/login"}
                  class="btn btn-sm btn-ghost hover:bg-base-200 transition-colors"
                >
                  Log in
                </.link>
              </li>
              <li>
                <.link
                  navigate={~p"/register"}
                  class="btn btn-sm btn-primary shadow-sm hover:shadow-md transition-all"
                >
                  Sign up
                </.link>
              </li>
            <% end %>
          </ul>
        </nav>
      </div>
    </header>
    """
  end
end
