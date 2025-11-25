defmodule ChatbotWeb.ChatLive.Index do
  @moduledoc """
  Main chat interface LiveView.

  Displays a list of conversations and allows creation of new conversations
  with streaming AI responses from LM Studio.
  """
  use ChatbotWeb, :live_view

  alias Chatbot.Chat
  alias ChatbotWeb.Live.Chat.StreamingHelpers

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id
    conversations = Chat.list_conversations(user_id)

    # Use the most recent conversation or create a new one if none exist
    conversation =
      case conversations do
        [most_recent | _] ->
          most_recent

        [] ->
          {:ok, new_conversation} =
            Chat.create_conversation(%{
              user_id: user_id,
              title: "New Conversation"
            })

          new_conversation
      end

    # Load messages for the conversation
    messages =
      if conversation.id do
        conversation = Chat.get_conversation_with_messages!(conversation.id, user_id)
        conversation.messages
      else
        []
      end

    socket =
      socket
      |> assign(:conversations, conversations)
      |> assign(:current_conversation, conversation)
      |> assign(:messages, messages)
      |> assign(:streaming_chunks, [])
      |> assign(:is_streaming, false)
      |> assign(:available_models, [])
      |> assign(:selected_model, conversation.model_name)
      |> assign(:models_loading, true)
      |> assign(:streaming_task_pid, nil)
      |> assign(:sidebar_open, false)
      |> assign(:form, to_form(%{"content" => ""}, as: :message))

    # Load available models asynchronously only on connected mount
    if connected?(socket) do
      send(self(), :load_models)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_models, socket) do
    socket = assign(socket, :models_loading, false)
    StreamingHelpers.handle_load_models(socket)
  end

  @impl true
  def handle_info({:chunk, content}, socket) do
    StreamingHelpers.handle_chunk(content, socket)
  end

  @impl true
  def handle_info({:done, _}, socket) do
    conversation_id = socket.assigns.current_conversation.id
    user_id = socket.assigns.current_user.id

    # Update conversations list
    socket = assign(socket, :conversations, Chat.list_conversations(user_id))

    StreamingHelpers.handle_done(conversation_id, user_id, socket)
  end

  @impl true
  def handle_info({:error, error_msg}, socket) do
    StreamingHelpers.handle_streaming_error(error_msg, socket)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    StreamingHelpers.handle_task_down(reason, socket)
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    StreamingHelpers.send_message_with_streaming(content, socket)
  end

  @impl true
  def handle_event("select_model", %{"model" => model_id}, socket) do
    StreamingHelpers.handle_select_model(model_id, socket)
  end

  @impl true
  def handle_event("new_conversation", _, socket) do
    user_id = socket.assigns.current_user.id

    {:ok, conversation} =
      Chat.create_conversation(%{
        user_id: user_id,
        title: "New Conversation"
      })

    {:noreply,
     socket
     |> assign(:current_conversation, conversation)
     |> assign(:messages, [])
     |> assign(:streaming_chunks, [])
     |> assign(:conversations, Chat.list_conversations(user_id))
     |> assign(:selected_model, conversation.model_name)}
  end

  @impl true
  def handle_event("toggle_sidebar", _, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-100 relative">
      <!-- Mobile Overlay -->
      <%= if @sidebar_open do %>
        <div
          class="fixed inset-0 bg-black/50 z-40 md:hidden"
          phx-click="toggle_sidebar"
          aria-label="Close sidebar"
        >
        </div>
      <% end %>
      
    <!-- Sidebar -->
      <aside
        aria-label="Conversations"
        class={[
          "w-72 bg-base-200 border-r border-base-300 flex flex-col z-50",
          "fixed md:relative inset-y-0 left-0",
          "transform transition-transform duration-200 ease-in-out",
          (@sidebar_open && "translate-x-0") || "-translate-x-full md:translate-x-0"
        ]}
      >
        <!-- Sidebar Header -->
        <div class="h-[61px] px-4 border-b border-base-300 flex items-center gap-2">
          <.button phx-click="new_conversation" class="flex-1 gap-2">
            <.icon name="hero-plus" class="w-4 h-4" /> New Chat
          </.button>
          <button
            phx-click="toggle_sidebar"
            class="btn btn-ghost btn-sm btn-square md:hidden"
            aria-label="Close sidebar"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
        
    <!-- Conversations List -->
        <div class="flex-1 overflow-y-auto">
          <%= for conversation <- @conversations do %>
            <.link
              navigate={~p"/chat/#{conversation.id}"}
              phx-click="toggle_sidebar"
              class={[
                "block p-3 hover:bg-base-300 border-b border-base-300 transition-colors",
                conversation.id == @current_conversation.id && "bg-base-300"
              ]}
            >
              <div class="flex items-center gap-2">
                <.icon name="hero-chat-bubble-left-right" class="w-4 h-4 text-base-content/50" />
                <span class="font-medium truncate flex-1">
                  {conversation.title || "New Conversation"}
                </span>
              </div>
              <div class="text-xs text-base-content/50 mt-1 ml-6">
                {Calendar.strftime(conversation.updated_at, "%b %d, %Y")}
              </div>
            </.link>
          <% end %>
        </div>
        
    <!-- User Section -->
        <div class="p-3 border-t border-base-300 bg-base-300/50">
          <div class="flex items-center gap-3">
            <div class="avatar placeholder">
              <div class="bg-primary text-primary-content rounded-full w-10">
                <span class="text-sm font-bold">
                  {String.first(@current_user.email) |> String.upcase()}
                </span>
              </div>
            </div>
            <div class="flex-1 min-w-0">
              <div class="text-sm font-medium truncate">{@current_user.email}</div>
            </div>
            <.link
              href={~p"/logout"}
              method="delete"
              class="btn btn-ghost btn-sm btn-square"
              aria-label="Logout"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" />
            </.link>
          </div>
        </div>
      </aside>
      
    <!-- Main Chat Area -->
      <main id="main-content" class="flex-1 flex flex-col w-full md:w-auto bg-base-100">
        <!-- Header -->
        <div class="h-[61px] bg-base-100 border-b border-base-300 px-4 flex items-center gap-3">
          <button
            phx-click="toggle_sidebar"
            class="btn btn-ghost btn-sm btn-square md:hidden"
            aria-label="Open sidebar"
          >
            <.icon name="hero-bars-3" class="w-5 h-5" />
          </button>

          <h2 class="text-lg font-semibold truncate flex-1">
            {@current_conversation.title || "New Conversation"}
          </h2>
          
    <!-- Model Selector Dropdown -->
          <div class="dropdown dropdown-end">
            <div
              tabindex="0"
              role="button"
              class="btn btn-ghost btn-sm gap-1"
              aria-label="Select AI model"
            >
              <.icon name="hero-cpu-chip" class="w-4 h-4" />
              <span class="hidden sm:inline max-w-[150px] truncate">
                {format_model_name(@selected_model)}
              </span>
              <.icon name="hero-chevron-down" class="w-3 h-3" />
            </div>
            <%= if not @models_loading do %>
              <ul
                tabindex="0"
                class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-box w-64 border border-base-300"
              >
                <%= for model <- @available_models do %>
                  <li>
                    <button
                      phx-click="select_model"
                      phx-value-model={model}
                      class={["text-left", model == @selected_model && "active"]}
                      disabled={@is_streaming}
                    >
                      <.icon name="hero-cpu-chip" class="w-4 h-4" />
                      <span class="truncate">{model}</span>
                      <%= if model == @selected_model do %>
                        <.icon name="hero-check" class="w-4 h-4 ml-auto" />
                      <% end %>
                    </button>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
        
    <!-- Chat Content -->
        <%= if @messages == [] and not @is_streaming do %>
          <!-- Empty State - Centered Input -->
          <div class="flex-1 flex flex-col items-center justify-center p-4">
            <div class="text-center mb-8">
              <div class="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center mx-auto mb-4">
                <.icon name="hero-chat-bubble-bottom-center-text" class="w-8 h-8 text-primary" />
              </div>
              <h3 class="text-xl font-semibold mb-2">Start a conversation</h3>
              <p class="text-base-content/60 max-w-md">
                Ask me anything! I can help with coding, writing, analysis, and much more.
              </p>
            </div>

            <div class="w-full max-w-2xl">
              <.form
                for={@form}
                phx-submit="send_message"
                class="flex flex-col gap-3"
                aria-label="Send message"
              >
                <textarea
                  name="message[content]"
                  placeholder="Type your message..."
                  rows="3"
                  class="textarea textarea-bordered w-full text-base resize-none focus:textarea-primary"
                  disabled={@is_streaming}
                  aria-label="Message input"
                ></textarea>
                <.button type="submit" disabled={@is_streaming} class="btn btn-primary self-end px-6">
                  <.icon name="hero-paper-airplane" class="w-4 h-4" /> Send
                </.button>
              </.form>
            </div>
          </div>
        <% else %>
          <!-- Messages -->
          <div
            class="flex-1 overflow-y-auto p-4"
            id="messages-container"
            role="log"
            aria-label="Chat messages"
            aria-live="polite"
            phx-hook="ScrollToBottom"
          >
            <div class="max-w-3xl mx-auto space-y-6">
              <%= for message <- @messages do %>
                <div class={[
                  "flex gap-3",
                  message.role == "user" && "flex-row-reverse"
                ]}>
                  <!-- Avatar -->
                  <div class={[
                    "w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0",
                    message.role == "user" && "bg-primary text-primary-content",
                    message.role != "user" && "bg-secondary text-secondary-content"
                  ]}>
                    <%= if message.role == "user" do %>
                      <.icon name="hero-user" class="w-4 h-4" />
                    <% else %>
                      <.icon name="hero-sparkles" class="w-4 h-4" />
                    <% end %>
                  </div>
                  
    <!-- Message Content -->
                  <div class={[
                    "flex-1 max-w-[80%]",
                    message.role == "user" && "text-right"
                  ]}>
                    <div class={[
                      "inline-block rounded-2xl px-4 py-2 text-left",
                      message.role == "user" && "bg-primary text-primary-content",
                      message.role != "user" && "bg-base-200"
                    ]}>
                      <div class="whitespace-pre-wrap">{message.content}</div>
                    </div>
                    <div class="text-xs text-base-content/40 mt-1 px-1">
                      {format_timestamp(message.inserted_at)}
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- Streaming Response -->
              <%= if @is_streaming do %>
                <div class="flex gap-3">
                  <div class="w-8 h-8 rounded-full bg-secondary text-secondary-content flex items-center justify-center flex-shrink-0">
                    <.icon name="hero-sparkles" class="w-4 h-4" />
                  </div>
                  <div class="flex-1 max-w-[80%]">
                    <div class="inline-block rounded-2xl px-4 py-2 bg-base-200">
                      <%= if @streaming_chunks != [] do %>
                        <div class="whitespace-pre-wrap">
                          {IO.iodata_to_binary(@streaming_chunks)}
                        </div>
                      <% end %>
                      <span class="loading loading-dots loading-sm"></span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
          
    <!-- Input Form (Fixed at Bottom) -->
          <div class="border-t border-base-300 bg-base-100 p-4">
            <div class="max-w-3xl mx-auto">
              <.form
                for={@form}
                phx-submit="send_message"
                class="flex gap-3 items-end"
                aria-label="Send message"
              >
                <textarea
                  name="message[content]"
                  placeholder="Type your message..."
                  rows="1"
                  class="textarea textarea-bordered flex-1 text-base resize-none min-h-[44px] max-h-[200px] focus:textarea-primary"
                  disabled={@is_streaming}
                  aria-label="Message input"
                  phx-hook="AutoGrowTextarea"
                  id="message-input"
                ></textarea>
                <.button
                  type="submit"
                  disabled={@is_streaming}
                  class="btn btn-primary btn-square"
                  aria-label="Send message"
                >
                  <%= if @is_streaming do %>
                    <span class="loading loading-spinner loading-sm"></span>
                  <% else %>
                    <.icon name="hero-paper-airplane" class="w-5 h-5" />
                  <% end %>
                </.button>
              </.form>
            </div>
          </div>
        <% end %>
      </main>
    </div>
    """
  end

  defp format_model_name(nil), do: "Select model"

  defp format_model_name(name) do
    name
    |> String.split("/")
    |> List.last()
    |> String.slice(0, 20)
  end

  defp format_timestamp(nil), do: ""

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end
end
