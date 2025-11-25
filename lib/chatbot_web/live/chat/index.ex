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
          "w-72 bg-base-200 flex flex-col z-50",
          "fixed md:relative inset-y-0 left-0",
          "transform transition-transform duration-200 ease-in-out",
          "shadow-lg md:shadow-none",
          (@sidebar_open && "translate-x-0") || "-translate-x-full md:translate-x-0"
        ]}
      >
        <!-- Sidebar Header -->
        <div class="h-16 px-4 flex items-center gap-2">
          <button
            phx-click="new_conversation"
            class="btn btn-primary flex-1 gap-2"
          >
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
        
    <!-- Conversations List -->
        <nav class="flex-1 overflow-y-auto px-2" aria-label="Conversation history">
          <%= for conversation <- @conversations do %>
            <.link
              navigate={~p"/chat/#{conversation.id}"}
              phx-click="toggle_sidebar"
              class={[
                "flex items-start gap-3 p-3 rounded-lg mb-1 transition-colors",
                "hover:bg-base-300 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 focus:ring-offset-base-200",
                conversation.id == @current_conversation.id && "bg-base-300"
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
        
    <!-- User Section -->
        <div class="p-3 border-t border-base-300">
          <div class="flex items-center gap-3 p-2 rounded-lg bg-base-300/50">
            <div class="avatar placeholder">
              <div class="bg-primary text-primary-content rounded-full w-9 h-9">
                <span class="text-sm font-semibold">
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
              class="btn btn-ghost btn-sm btn-square hover:bg-base-300"
              aria-label="Logout"
              title="Sign out"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" />
            </.link>
          </div>
        </div>
      </aside>
      
    <!-- Main Chat Area -->
      <main id="main-content" class="flex-1 flex flex-col w-full md:w-auto bg-base-100">
        <!-- Header -->
        <header class="h-16 bg-base-100 border-b border-base-300 px-4 flex items-center gap-3">
          <button
            phx-click="toggle_sidebar"
            class="btn btn-ghost btn-sm btn-square md:hidden"
            aria-label="Open sidebar"
          >
            <.icon name="hero-bars-3" class="w-5 h-5" />
          </button>

          <div class="flex-1 min-w-0">
            <h1 class="text-lg font-semibold truncate">
              {@current_conversation.title || "New Conversation"}
            </h1>
          </div>
          
    <!-- Model Selector -->
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
                      class={[
                        "flex items-center gap-2 rounded-lg",
                        model == @selected_model && "active"
                      ]}
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
        </header>
        
    <!-- Chat Content -->
        <%= if @messages == [] and not @is_streaming do %>
          <!-- Empty State -->
          <div class="flex-1 flex flex-col items-center justify-center p-6">
            <div class="text-center mb-8 max-w-md">
              <div class="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-6">
                <.icon name="hero-chat-bubble-bottom-center-text" class="w-8 h-8 text-primary" />
              </div>
              <h2 class="text-2xl font-semibold mb-3">How can I help you today?</h2>
              <p class="text-base-content/60">
                I can help with coding, writing, analysis, brainstorming, and much more. Just type your message below.
              </p>
            </div>
            
    <!-- Input for empty state -->
            <div class="w-full max-w-2xl">
              <.form
                for={@form}
                phx-submit="send_message"
                aria-label="Send message"
              >
                <div class="relative">
                  <textarea
                    name="message[content]"
                    placeholder="Type your message..."
                    rows="3"
                    class="textarea textarea-bordered w-full text-base resize-none pr-14 focus:textarea-primary focus:outline-none"
                    disabled={@is_streaming}
                    aria-label="Message input"
                    id="empty-state-input"
                    phx-hook="AutoGrowTextarea"
                  ></textarea>
                  <button
                    type="submit"
                    disabled={@is_streaming}
                    class="absolute right-3 bottom-3 btn btn-primary btn-sm btn-circle"
                    aria-label="Send message"
                  >
                    <.icon name="hero-arrow-up" class="w-4 h-4" />
                  </button>
                </div>
              </.form>
            </div>
          </div>
        <% else %>
          <!-- Messages Area -->
          <div
            class="flex-1 overflow-y-auto flex flex-col-reverse"
            id="messages-container"
            role="log"
            aria-label="Chat messages"
            aria-live="polite"
            phx-hook="ScrollToBottom"
          >
            <div class="max-w-3xl mx-auto py-6 px-4 space-y-6">
              <%= for message <- @messages do %>
                <div class={[
                  "flex gap-4",
                  message.role == "user" && "flex-row-reverse"
                ]}>
                  <!-- Avatar -->
                  <div class={[
                    "w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0",
                    message.role == "user" && "bg-primary text-primary-content",
                    message.role != "user" &&
                      "bg-gradient-to-br from-violet-500 to-purple-600 text-white"
                  ]}>
                    <%= if message.role == "user" do %>
                      <.icon name="hero-user" class="w-4 h-4" />
                    <% else %>
                      <.icon name="hero-sparkles" class="w-4 h-4" />
                    <% end %>
                  </div>
                  
    <!-- Message Content -->
                  <div class={[
                    "flex-1 min-w-0",
                    message.role == "user" && "flex flex-col items-end"
                  ]}>
                    <div class={[
                      "inline-block rounded-2xl px-4 py-3 max-w-[85%]",
                      message.role == "user" && "bg-primary text-primary-content rounded-br-md",
                      message.role != "user" &&
                        "bg-base-200 rounded-bl-md border border-base-300 shadow-sm"
                    ]}>
                      <.markdown content={message.content} />
                    </div>
                    <div class="text-xs text-base-content/40 mt-1.5 px-1">
                      {format_timestamp(message.inserted_at)}
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- Streaming Response -->
              <%= if @is_streaming do %>
                <div class="flex gap-4">
                  <div class="w-8 h-8 rounded-full bg-gradient-to-br from-violet-500 to-purple-600 text-white flex items-center justify-center flex-shrink-0">
                    <.icon name="hero-sparkles" class="w-4 h-4" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="inline-block rounded-2xl rounded-bl-md px-4 py-3 bg-base-200 border border-base-300 shadow-sm max-w-[85%]">
                      <%= if @streaming_chunks != [] do %>
                        <.markdown content={IO.iodata_to_binary(@streaming_chunks)} />
                      <% end %>
                      <span class="loading loading-dots loading-sm text-primary"></span>
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
                aria-label="Send message"
              >
                <div class="relative flex items-end gap-2 bg-base-200 rounded-2xl p-2 focus-within:ring-2 focus-within:ring-primary focus-within:ring-offset-2 focus-within:ring-offset-base-100 transition-shadow">
                  <textarea
                    name="message[content]"
                    placeholder="Type your message..."
                    rows="1"
                    class="flex-1 bg-transparent border-none text-base resize-none min-h-[40px] max-h-[200px] py-2 px-3 focus:outline-none placeholder:text-base-content/40"
                    disabled={@is_streaming}
                    aria-label="Message input"
                    phx-hook="AutoGrowTextarea"
                    id="message-input"
                  ></textarea>
                  <button
                    type="submit"
                    disabled={@is_streaming}
                    class={[
                      "btn btn-circle btn-sm flex-shrink-0 transition-all",
                      @is_streaming && "btn-ghost",
                      !@is_streaming && "btn-primary"
                    ]}
                    aria-label="Send message"
                  >
                    <%= if @is_streaming do %>
                      <span class="loading loading-spinner loading-sm"></span>
                    <% else %>
                      <.icon name="hero-arrow-up" class="w-4 h-4" />
                    <% end %>
                  </button>
                </div>
                <p class="text-xs text-center text-base-content/40 mt-2">
                  Press Enter to send, Shift+Enter for new line
                </p>
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
    short_name =
      name
      |> String.split("/")
      |> List.last()

    if String.length(short_name) > 20 do
      String.slice(short_name, 0, 17) <> "..."
    else
      short_name
    end
  end

  defp format_timestamp(nil), do: ""

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end
end
