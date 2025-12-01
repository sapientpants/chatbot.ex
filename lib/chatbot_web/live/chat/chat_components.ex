defmodule ChatbotWeb.Live.Chat.ChatComponents do
  @moduledoc """
  Shared UI components for chat LiveViews.

  Provides the sidebar and model selector components.
  For message display, see `MessageComponents`.
  For input forms, see `InputComponents`.
  """
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: ChatbotWeb.Endpoint, router: ChatbotWeb.Router

  import ChatbotWeb.CoreComponents

  # Re-export components from extracted modules for backwards compatibility
  defdelegate chat_message(assigns), to: ChatbotWeb.Live.Chat.MessageComponents
  defdelegate streaming_response(assigns), to: ChatbotWeb.Live.Chat.MessageComponents
  defdelegate messages_container(assigns), to: ChatbotWeb.Live.Chat.MessageComponents
  defdelegate format_timestamp(datetime), to: ChatbotWeb.Live.Chat.MessageComponents
  defdelegate message_input_form(assigns), to: ChatbotWeb.Live.Chat.InputComponents
  defdelegate empty_chat_state(assigns), to: ChatbotWeb.Live.Chat.InputComponents

  @doc "Renders the mobile overlay for the sidebar."
  attr :sidebar_open, :boolean, required: true

  @spec mobile_overlay(map()) :: Phoenix.LiveView.Rendered.t()
  def mobile_overlay(assigns) do
    ~H"""
    <%= if @sidebar_open do %>
      <div
        class="fixed inset-0 bg-black/50 z-40 md:hidden"
        phx-click="toggle_sidebar"
        aria-label="Close sidebar"
      >
      </div>
    <% end %>
    """
  end

  @doc "Renders the chat sidebar with conversations list and user section."
  attr :sidebar_open, :boolean, required: true
  attr :conversations, :list, required: true
  attr :current_conversation, :any, required: true
  attr :current_user, :any, required: true

  @spec chat_sidebar(map()) :: Phoenix.LiveView.Rendered.t()
  def chat_sidebar(assigns) do
    ~H"""
    <aside
      aria-label="Conversations"
      class={[
        "w-72 bg-base-200 flex flex-col z-50",
        "fixed md:relative inset-y-0 left-0",
        "transform transition-transform duration-200 ease-in-out",
        "shadow-lg md:shadow-none",
        (@sidebar_open && "translate-x-0") || "-translate-x-full md:translate-x-0"
      ]}
    >
      <div class="h-16 px-4 flex items-center gap-2">
        <button phx-click="new_conversation" class="btn btn-primary flex-1 gap-2">
          <.icon name="hero-plus" class="w-4 h-4" /> New Chat
        </button>
        <button
          phx-click="toggle_sidebar"
          class="btn btn-ghost btn-sm btn-square md:hidden"
          aria-label="Close sidebar"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>
      <nav class="flex-1 overflow-y-auto px-2" aria-label="Conversation history">
        <%= for conversation <- @conversations do %>
          <.link
            navigate={~p"/chat/#{conversation.id}"}
            phx-click="toggle_sidebar"
            class={[
              "flex items-start gap-3 p-3 rounded-lg mb-1 transition-colors",
              "hover:bg-base-300 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 focus:ring-offset-base-200",
              @current_conversation && conversation.id == @current_conversation.id && "bg-base-300"
            ]}
          >
            <.icon
              name="hero-chat-bubble-left"
              class="w-5 h-5 text-base-content/60 mt-0.5 flex-shrink-0"
            />
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate text-sm">
                {conversation.title || "New Conversation"}
              </div>
              <div class="text-xs text-base-content/50 mt-0.5">
                {Calendar.strftime(conversation.updated_at, "%b %d, %Y")}
              </div>
            </div>
          </.link>
        <% end %>
      </nav>
      <.user_section current_user={@current_user} />
    </aside>
    """
  end

  defp user_section(assigns) do
    ~H"""
    <div class="p-3 border-t border-base-300">
      <div class="flex items-center gap-3 p-2 rounded-lg">
        <div class="bg-primary text-primary-content rounded-full w-9 h-9 flex items-center justify-center shrink-0">
          <span class="text-sm font-semibold text-center">{get_initials(@current_user.email)}</span>
        </div>
        <div class="flex-1 min-w-0">
          <div class="text-sm font-medium truncate">{@current_user.email}</div>
        </div>
        <.link
          navigate={~p"/settings"}
          class="btn btn-ghost btn-sm btn-square hover:bg-base-300"
          aria-label="Settings"
          title="Provider settings"
        >
          <.icon name="hero-cog-6-tooth" class="w-5 h-5" />
        </.link>
        <.link
          href={~p"/logout"}
          method="delete"
          class="btn btn-ghost btn-sm btn-square hover:bg-base-300"
          aria-label="Logout"
          title="Sign out"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" />
        </.link>
      </div>
    </div>
    """
  end

  @doc "Renders the model selector dropdown."
  attr :selected_model, :string, default: nil
  attr :available_models, :list, required: true
  attr :models_loading, :boolean, required: true
  attr :is_streaming, :boolean, required: true

  @spec model_selector(map()) :: Phoenix.LiveView.Rendered.t()
  def model_selector(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <button
        tabindex="0"
        class="btn btn-sm btn-ghost gap-2 font-normal"
        aria-label="Select AI model"
        aria-haspopup="true"
      >
        <.icon name="hero-cpu-chip" class="w-4 h-4 text-primary" />
        <span class="hidden sm:inline max-w-[120px] truncate text-base-content/70">
          {format_model_name(@selected_model)}
        </span>
        <.icon name="hero-chevron-down" class="w-3 h-3 text-base-content/50" />
      </button>
      <%= if not @models_loading do %>
        <ul
          tabindex="0"
          class="dropdown-content z-[1] menu p-2 shadow-xl bg-base-100 rounded-xl w-72 border border-base-200 mt-2"
        >
          <li class="menu-title text-xs uppercase tracking-wider text-base-content/50 px-2 py-1">
            Select Model
          </li>
          <%= for model <- @available_models do %>
            <li>
              <button
                phx-click="select_model"
                phx-value-model={model}
                class={["flex items-center gap-2 rounded-lg", model == @selected_model && "active"]}
                disabled={@is_streaming}
              >
                <.icon name="hero-cpu-chip" class="w-4 h-4" />
                <span class="flex-1 truncate text-left">{model}</span>
                <%= if model == @selected_model do %>
                  <.icon name="hero-check" class="w-4 h-4 text-primary" />
                <% end %>
              </button>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end

  @doc "Formats a model name for display, truncating if necessary."
  @spec format_model_name(String.t() | nil) :: String.t()
  def format_model_name(nil), do: "Select model"

  def format_model_name(name) do
    max_length = Application.get_env(:chatbot, :ui, [])[:max_model_name_length] || 20
    short_name = name |> String.split("/") |> List.last()

    if String.length(short_name) > max_length,
      do: String.slice(short_name, 0, max_length - 3) <> "...",
      else: short_name
  end

  @doc "Extracts initials from an email address."
  @spec get_initials(String.t()) :: String.t()
  def get_initials(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first("")
    |> String.split(~r/[._-]/)
    |> Enum.map(&String.first/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  def get_initials(_email), do: "?"
end
