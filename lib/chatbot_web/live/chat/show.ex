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
    <div class="flex h-screen bg-base-200 relative">
      <!-- Mobile Overlay -->
      <%= if @sidebar_open do %>
        <div
          class="fixed inset-0 bg-black bg-opacity-50 z-40 md:hidden"
          phx-click="toggle_sidebar"
        >
        </div>
      <% end %>
      
    <!-- Sidebar -->
      <div class={[
        "w-64 bg-base-100 border-r border-base-300 flex flex-col z-50",
        "fixed md:relative inset-y-0 left-0",
        "transform transition-transform duration-200 ease-in-out",
        (@sidebar_open && "translate-x-0") || "-translate-x-full md:translate-x-0"
      ]}>
        <div class="p-4 border-b border-base-300 flex items-center justify-between">
          <.button phx-click="new_conversation" class="flex-1">
            New Chat
          </.button>
          <button phx-click="toggle_sidebar" class="ml-2 btn btn-ghost btn-sm md:hidden">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-5 h-5"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <%= for conversation <- @conversations do %>
            <.link
              navigate={~p"/chat/#{conversation.id}"}
              phx-click="toggle_sidebar"
              class={[
                "block p-3 hover:bg-base-200 border-b border-base-300",
                conversation.id == @current_conversation.id && "bg-base-200"
              ]}
            >
              <div class="font-medium truncate">{conversation.title || "New Conversation"}</div>
              <div class="text-xs text-gray-500">
                {Calendar.strftime(conversation.updated_at, "%b %d, %Y")}
              </div>
            </.link>
          <% end %>
        </div>

        <div class="p-4 border-t border-base-300">
          <div class="text-sm text-gray-600">{@current_user.email}</div>
          <.link href={~p"/logout"} method="delete" class="text-sm text-blue-600 hover:underline">
            Logout
          </.link>
        </div>
      </div>
      
    <!-- Main Chat Area -->
      <div class="flex-1 flex flex-col w-full md:w-auto">
        <!-- Header with hamburger menu, model selection and actions -->
        <div class="bg-base-100 border-b border-base-300 p-4 flex items-center justify-between gap-2">
          <div class="flex items-center gap-2 flex-1 min-w-0">
            <button phx-click="toggle_sidebar" class="btn btn-ghost btn-sm md:hidden flex-shrink-0">
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
                  d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"
                />
              </svg>
            </button>
            <h2 class="text-lg md:text-xl font-bold truncate">
              {@current_conversation.title || "New Conversation"}
            </h2>
          </div>

          <div class="flex items-center gap-2 md:gap-4 flex-shrink-0">
            <div class="flex items-center gap-2">
              <label class="text-xs md:text-sm hidden sm:inline">Model:</label>
              <%= if @models_loading do %>
                <span class="loading loading-spinner loading-sm"></span>
              <% else %>
                <select
                  phx-change="select_model"
                  name="model"
                  class="select select-xs md:select-sm select-bordered"
                  disabled={@is_streaming}
                >
                  <%= for model <- @available_models do %>
                    <option value={model} selected={model == @selected_model}>
                      {model}
                    </option>
                  <% end %>
                </select>
              <% end %>
            </div>

            <div class="dropdown dropdown-end">
              <label tabindex="0" class="btn btn-xs md:btn-sm btn-ghost">
                Actions
              </label>
              <ul
                tabindex="0"
                class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52"
              >
                <li>
                  <a phx-click="export_markdown">Export as Markdown</a>
                </li>
                <li>
                  <a phx-click="export_json">Export as JSON</a>
                </li>
                <li>
                  <a phx-click="show_delete_modal">
                    Delete Conversation
                  </a>
                </li>
              </ul>
            </div>
          </div>
        </div>
        
    <!-- Messages -->
        <div class="flex-1 overflow-y-auto p-4 space-y-4" id="messages-container">
          <%= for message <- @messages do %>
            <div class={["chat", (message.role == "user" && "chat-end") || "chat-start"]}>
              <div class="chat-bubble">
                <div class="whitespace-pre-wrap">{message.content}</div>
              </div>
            </div>
          <% end %>

          <%= if @is_streaming and @streaming_chunks != [] do %>
            <div class="chat chat-start">
              <div class="chat-bubble">
                <div class="whitespace-pre-wrap">{IO.iodata_to_binary(@streaming_chunks)}</div>
                <span class="loading loading-dots loading-sm"></span>
              </div>
            </div>
          <% end %>

          <%= if @is_streaming and @streaming_chunks == [] do %>
            <div class="chat chat-start">
              <div class="chat-bubble">
                <span class="loading loading-dots loading-md"></span>
              </div>
            </div>
          <% end %>
        </div>
        
    <!-- Input Form -->
        <div class="bg-base-100 border-t border-base-300 p-4">
          <.form for={@form} phx-submit="send_message" class="flex gap-2">
            <.input
              field={@form[:content]}
              type="textarea"
              placeholder="Type your message..."
              class="flex-1"
              disabled={@is_streaming}
            />
            <.button type="submit" disabled={@is_streaming}>
              <%= if @is_streaming do %>
                <span class="loading loading-spinner"></span>
              <% else %>
                Send
              <% end %>
            </.button>
          </.form>
        </div>
      </div>
      
    <!-- Delete Confirmation Modal -->
      <%= if @show_delete_modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg">Delete Conversation?</h3>
            <p class="py-4">
              Are you sure you want to delete "{@current_conversation.title}"? This action cannot be undone.
            </p>
            <div class="modal-action">
              <button class="btn btn-ghost" phx-click="hide_delete_modal">Cancel</button>
              <button class="btn btn-error" phx-click="confirm_delete_conversation">Delete</button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
