defmodule ChatbotWeb.ChatLive.Show do
  @moduledoc """
  Individual conversation view LiveView.

  Displays a specific conversation with its message history and allows
  continuing the conversation with streaming AI responses.
  """
  use ChatbotWeb, :live_view

  import ChatbotWeb.Live.Chat.ChatComponents

  alias Chatbot.Chat
  alias ChatbotWeb.Live.Chat.StreamingHelpers

  @impl Phoenix.LiveView
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
        |> stream(:messages, conversation.messages)
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

  @impl Phoenix.LiveView
  def handle_info(:load_models, socket) do
    socket = assign(socket, :models_loading, false)
    StreamingHelpers.handle_load_models(socket)
  end

  @impl Phoenix.LiveView
  def handle_info({:chunk, content}, socket) do
    StreamingHelpers.handle_chunk(content, socket)
  end

  @impl Phoenix.LiveView
  def handle_info({:done, _metadata}, socket) do
    StreamingHelpers.handle_done(socket)
  end

  @impl Phoenix.LiveView
  def handle_info({:error, error_msg}, socket) do
    StreamingHelpers.handle_streaming_error(error_msg, socket)
  end

  @impl Phoenix.LiveView
  def handle_info({:DOWN, _ref, :process, _task_pid, reason}, socket) do
    StreamingHelpers.handle_task_down(reason, socket)
  end

  @impl Phoenix.LiveView
  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    StreamingHelpers.send_message_with_streaming(content, socket)
  end

  @impl Phoenix.LiveView
  def handle_event("select_model", %{"model" => model_id}, socket) do
    StreamingHelpers.handle_select_model(model_id, socket)
  end

  @impl Phoenix.LiveView
  def handle_event("new_conversation", _params, socket) do
    StreamingHelpers.handle_new_conversation(socket, redirect_to: ~p"/chat")
  end

  @impl Phoenix.LiveView
  def handle_event("show_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  @impl Phoenix.LiveView
  def handle_event("hide_delete_modal", _params, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  @impl Phoenix.LiveView
  def handle_event("confirm_delete_conversation", _params, socket) do
    user_id = socket.assigns.current_user.id

    case Chat.delete_conversation(socket.assigns.current_conversation, user_id) do
      {:ok, _deleted} ->
        {:noreply,
         socket
         |> put_flash(:info, "Conversation deleted")
         |> push_navigate(to: ~p"/chat")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete conversation")
         |> assign(:show_delete_modal, false)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl Phoenix.LiveView
  def handle_event("export_markdown", _params, socket) do
    conversation = socket.assigns.current_conversation
    # Reload messages from database for export (streams don't store list)
    messages = Chat.list_messages(conversation.id)

    markdown_content = export_as_markdown(conversation, messages)

    # Send the markdown as a download
    {:noreply,
     push_event(socket, "download", %{
       filename: "#{conversation.title || "conversation"}.md",
       content: markdown_content
     })}
  end

  @impl Phoenix.LiveView
  def handle_event("export_json", _params, socket) do
    conversation = socket.assigns.current_conversation
    # Reload messages from database for export (streams don't store list)
    messages = Chat.list_messages(conversation.id)

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
     push_event(socket, "download", %{
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

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-100 relative">
      <.mobile_overlay sidebar_open={@sidebar_open} />

      <.chat_sidebar
        sidebar_open={@sidebar_open}
        conversations={@conversations}
        current_conversation={@current_conversation}
        current_user={@current_user}
      />
      
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

          <.model_selector
            selected_model={@selected_model}
            available_models={@available_models}
            models_loading={@models_loading}
            is_streaming={@is_streaming}
          />
          
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

        <.messages_container
          messages={@streams.messages}
          is_streaming={@is_streaming}
          streaming_chunks={@streaming_chunks}
        />
        <.message_input_form form={@form} is_streaming={@is_streaming} />
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
end
