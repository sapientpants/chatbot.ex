defmodule ChatbotWeb.ChatLive.Index do
  @moduledoc """
  Main chat interface LiveView.

  Displays a list of conversations and allows creation of new conversations
  with streaming AI responses from LM Studio.
  """
  use ChatbotWeb, :live_view

  import ChatbotWeb.Live.Chat.ChatComponents

  alias Chatbot.Chat
  alias ChatbotWeb.Live.Chat.StreamingHelpers

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id
    conversations = Chat.list_conversations(user_id)

    # Use the most recent conversation or create a new one if none exist
    conversation =
      case conversations do
        [most_recent | _rest] ->
          most_recent

        [] ->
          case Chat.create_conversation(%{
                 user_id: user_id,
                 title: "New Conversation"
               }) do
            {:ok, new_conversation} ->
              new_conversation

            {:error, _changeset} ->
              # Return nil and handle in template
              nil
          end
      end

    # Load messages for the conversation
    messages =
      if conversation && conversation.id do
        conv_with_messages = Chat.get_conversation_with_messages!(conversation.id, user_id)
        conv_with_messages.messages
      else
        []
      end

    socket =
      socket
      |> assign(:conversations, conversations)
      |> assign(:current_conversation, conversation)
      |> stream(:messages, messages)
      |> assign(:has_messages, messages != [])
      |> assign(:streaming_chunks, [])
      |> assign(:is_streaming, false)
      |> assign(:available_models, [])
      |> assign(:selected_model, if(conversation, do: conversation.model_name, else: nil))
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
    conversation_id = socket.assigns.current_conversation.id
    user_id = socket.assigns.current_user.id

    # StreamingHelpers.handle_done updates conversations list locally
    StreamingHelpers.handle_done(conversation_id, user_id, socket)
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
    user_id = socket.assigns.current_user.id

    case Chat.create_conversation(%{
           user_id: user_id,
           title: "New Conversation"
         }) do
      {:ok, conversation} ->
        # Prepend new conversation to list instead of reloading from DB
        conversations = [conversation | socket.assigns.conversations]

        {:noreply,
         socket
         |> assign(:current_conversation, conversation)
         |> stream(:messages, [], reset: true)
         |> assign(:has_messages, false)
         |> assign(:streaming_chunks, [])
         |> assign(:conversations, conversations)
         |> assign(:selected_model, conversation.model_name)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create conversation")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
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
              {(@current_conversation && @current_conversation.title) || "New Conversation"}
            </h1>
          </div>

          <.model_selector
            selected_model={@selected_model}
            available_models={@available_models}
            models_loading={@models_loading}
            is_streaming={@is_streaming}
          />
        </header>
        
    <!-- Chat Content -->
        <%= if not @has_messages and not @is_streaming do %>
          <.empty_chat_state form={@form} is_streaming={@is_streaming} />
        <% else %>
          <.messages_container
            messages={@streams.messages}
            is_streaming={@is_streaming}
            streaming_chunks={@streaming_chunks}
          />
          <.message_input_form form={@form} is_streaming={@is_streaming} />
        <% end %>
      </main>
    </div>
    """
  end
end
