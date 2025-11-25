defmodule ChatbotWeb.ChatLive.Show do
  @moduledoc """
  Individual conversation view LiveView.

  Displays a specific conversation with its message history and allows
  continuing the conversation with streaming AI responses.
  """
  use ChatbotWeb, :live_view

  alias Chatbot.Chat
  alias ChatbotWeb.Live.Chat.StreamingHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_user.id

    # Get conversation with authorization check
    conversation =
      try do
        Chat.get_conversation_with_messages!(id, user_id)
      rescue
        Ecto.NoResultsError ->
          nil
      end

    if conversation == nil do
      {:ok,
       socket
       |> put_flash(:error, "Conversation not found")
       |> redirect(to: ~p"/chat")}
    else
      socket =
        socket
        |> assign(:conversations, Chat.list_conversations(user_id))
        |> assign(:current_conversation, conversation)
        |> assign(:messages, conversation.messages)
        |> assign(:streaming_chunks, [])
        |> assign(:is_streaming, false)
        |> assign(:available_models, [])
        |> assign(:selected_model, conversation.model_name)
        |> assign(:models_loading, true)
        |> assign(:show_delete_modal, false)
        |> assign(:streaming_task_pid, nil)
        |> assign(:sidebar_open, false)
        |> assign(:form, to_form(%{"content" => ""}, as: :message))

      # Load available models asynchronously only on connected mount
      if connected?(socket) do
        send(self(), :load_models)
      end

      {:ok, socket}
    end
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
    StreamingHelpers.handle_new_conversation(socket, ~p"/chat")
  end

  @impl true
  def handle_event("show_delete_modal", _, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  @impl true
  def handle_event("hide_delete_modal", _, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  @impl true
  def handle_event("confirm_delete_conversation", _, socket) do
    user_id = socket.assigns.current_user.id

    case Chat.delete_conversation(socket.assigns.current_conversation, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Conversation deleted")
         |> push_navigate(to: ~p"/chat")}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete conversation")
         |> assign(:show_delete_modal, false)}
    end
  end

  @impl true
  def handle_event("toggle_sidebar", _, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl true
  def handle_event("export_markdown", _, socket) do
    conversation = socket.assigns.current_conversation
    messages = socket.assigns.messages

    markdown_content = export_as_markdown(conversation, messages)

    # Send the markdown as a download
    {:noreply,
     socket
     |> push_event("download", %{
       filename: "#{conversation.title || "conversation"}.md",
       content: markdown_content
     })}
  end

  @impl true
  def handle_event("export_json", _, socket) do
    conversation = socket.assigns.current_conversation
    messages = socket.assigns.messages

    json_content =
      Jason.encode!(
        %{
          title: conversation.title,
          model: conversation.model_name,
          created_at: conversation.inserted_at,
          updated_at: conversation.updated_at,
          messages:
            Enum.map(messages, fn msg ->
              %{
                role: msg.role,
                content: msg.content,
                timestamp: msg.inserted_at
              }
            end)
        },
        pretty: true
      )

    {:noreply,
     socket
     |> push_event("download", %{
       filename: "#{conversation.title || "conversation"}.json",
       content: json_content
     })}
  end

  defp export_as_markdown(conversation, messages) do
    header = """
    # #{conversation.title || "Conversation"}

    **Model:** #{conversation.model_name || "N/A"}
    **Created:** #{Calendar.strftime(conversation.inserted_at, "%B %d, %Y at %I:%M %p")}

    ---

    """

    messages_md =
      Enum.map_join(messages, "\n---\n\n", fn msg ->
        role_label = if msg.role == "user", do: "**You:**", else: "**Assistant:**"

        """
        #{role_label}

        #{msg.content}

        """
      end)

    header <> messages_md
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
          
    <!-- Actions Menu -->
          <div class="dropdown dropdown-end">
            <button
              tabindex="0"
              class="btn btn-sm btn-ghost btn-square"
              aria-label="Conversation actions"
            >
              <.icon name="hero-ellipsis-vertical" class="w-5 h-5" />
            </button>
            <ul
              tabindex="0"
              class="dropdown-content z-[1] menu p-2 shadow-xl bg-base-100 rounded-xl w-52 border border-base-200 mt-2"
              role="menu"
            >
              <li role="none">
                <button phx-click="export_markdown" role="menuitem" class="flex items-center gap-2">
                  <.icon name="hero-document-text" class="w-4 h-4" /> Export as Markdown
                </button>
              </li>
              <li role="none">
                <button phx-click="export_json" role="menuitem" class="flex items-center gap-2">
                  <.icon name="hero-code-bracket" class="w-4 h-4" /> Export as JSON
                </button>
              </li>
              <li role="none" class="border-t border-base-200 mt-1 pt-1">
                <button
                  phx-click="show_delete_modal"
                  role="menuitem"
                  class="flex items-center gap-2 text-error"
                >
                  <.icon name="hero-trash" class="w-4 h-4" /> Delete Conversation
                </button>
              </li>
            </ul>
          </div>
        </header>
        
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
      </main>
      
    <!-- Delete Confirmation Modal -->
      <%= if @show_delete_modal do %>
        <div class="modal modal-open" role="dialog" aria-labelledby="modal-title" aria-modal="true">
          <div class="modal-box">
            <h3 id="modal-title" class="font-bold text-lg flex items-center gap-2">
              <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-warning" />
              Delete Conversation?
            </h3>
            <p class="py-4 text-base-content/70">
              Are you sure you want to delete "<span class="font-medium text-base-content">{@current_conversation.title}</span>"? This action cannot be undone.
            </p>
            <div class="modal-action">
              <button class="btn btn-ghost" phx-click="hide_delete_modal">Cancel</button>
              <button class="btn btn-error gap-2" phx-click="confirm_delete_conversation">
                <.icon name="hero-trash" class="w-4 h-4" /> Delete
              </button>
            </div>
          </div>
          <div class="modal-backdrop bg-black/50" phx-click="hide_delete_modal"></div>
        </div>
      <% end %>
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
