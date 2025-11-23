defmodule ChatbotWeb.ChatLive.Index do
  @moduledoc """
  Main chat interface LiveView.

  Displays a list of conversations and allows creation of new conversations
  with streaming AI responses from LM Studio.
  """
  use ChatbotWeb, :live_view

  alias Chatbot.Chat
  alias Chatbot.LMStudio

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id

    # Create a new conversation for the user
    {:ok, conversation} =
      Chat.create_conversation(%{
        user_id: user_id,
        title: "New Conversation"
      })

    socket =
      socket
      |> assign(:conversations, Chat.list_conversations(user_id))
      |> assign(:current_conversation, conversation)
      |> assign(:messages, [])
      |> assign(:streaming_message, "")
      |> assign(:is_streaming, false)
      |> assign(:available_models, [])
      |> assign(:selected_model, nil)
      |> assign(:models_loading, true)
      |> assign(:form, to_form(%{"content" => ""}, as: :message))

    # Load available models asynchronously
    send(self(), :load_models)

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_models, socket) do
    case LMStudio.list_models() do
      {:ok, models} ->
        selected_model = if length(models) > 0, do: hd(models)["id"], else: nil

        {:noreply,
         socket
         |> assign(:available_models, models)
         |> assign(:selected_model, selected_model)
         |> assign(:models_loading, false)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not connect to LM Studio. Is it running?")
         |> assign(:models_loading, false)}
    end
  end

  @impl true
  def handle_info({:chunk, content}, socket) do
    {:noreply, assign(socket, :streaming_message, socket.assigns.streaming_message <> content)}
  end

  @impl true
  def handle_info({:done, _}, socket) do
    # Save the complete assistant message
    conversation_id = socket.assigns.current_conversation.id
    user_id = socket.assigns.current_user.id
    assistant_message = socket.assigns.streaming_message

    {:ok, _message} =
      Chat.create_message(%{
        conversation_id: conversation_id,
        role: "assistant",
        content: assistant_message
      })

    # Reload messages
    conversation = Chat.get_conversation_with_messages!(conversation_id, user_id)

    {:noreply,
     socket
     |> assign(:messages, conversation.messages)
     |> assign(:streaming_message, "")
     |> assign(:is_streaming, false)
     |> assign(:current_conversation, conversation)}
  end

  @impl true
  def handle_info({:error, error_msg}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Error: #{error_msg}")
     |> assign(:is_streaming, false)
     |> assign(:streaming_message, "")}
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    if String.trim(content) == "" do
      {:noreply, socket}
    else
      conversation_id = socket.assigns.current_conversation.id
      user_id = socket.assigns.current_user.id

      # Save user message
      {:ok, _message} =
        Chat.create_message(%{
          conversation_id: conversation_id,
          role: "user",
          content: content
        })

      # Update conversation title if it's the first message
      socket =
        if socket.assigns.current_conversation.title == "New Conversation" do
          title = Chat.generate_conversation_title(content)

          {:ok, updated_conversation} =
            Chat.update_conversation(socket.assigns.current_conversation, %{title: title})

          socket
          |> assign(:current_conversation, updated_conversation)
          |> assign(:conversations, Chat.list_conversations(user_id))
        else
          socket
        end

      # Reload conversation with messages
      conversation = Chat.get_conversation_with_messages!(conversation_id, user_id)
      messages = conversation.messages

      # Build OpenAI format messages
      openai_messages = Chat.build_openai_messages(messages)

      # Start streaming response from LM Studio
      model = socket.assigns.selected_model || "default"

      # Capture LiveView PID before starting Task
      liveview_pid = self()

      Task.Supervisor.start_child(Chatbot.TaskSupervisor, fn ->
        LMStudio.stream_chat_completion(openai_messages, model, liveview_pid)
      end)

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:streaming_message, "")
       |> assign(:is_streaming, true)
       |> assign(:form, to_form(%{"content" => ""}, as: :message))}
    end
  end

  @impl true
  def handle_event("select_model", %{"model" => model_id}, socket) do
    {:noreply, assign(socket, :selected_model, model_id)}
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
     |> assign(:conversations, Chat.list_conversations(user_id))
     |> push_navigate(to: ~p"/chat")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-200">
      <!-- Sidebar -->
      <div class="w-64 bg-base-100 border-r border-base-300 flex flex-col">
        <div class="p-4 border-b border-base-300">
          <.button phx-click="new_conversation" class="w-full">
            New Chat
          </.button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <%= for conversation <- @conversations do %>
            <.link
              navigate={~p"/chat/#{conversation.id}"}
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
      <div class="flex-1 flex flex-col">
        <!-- Header with model selection -->
        <div class="bg-base-100 border-b border-base-300 p-4 flex items-center justify-between">
          <h2 class="text-xl font-bold">{@current_conversation.title || "New Conversation"}</h2>

          <div class="flex items-center gap-2">
            <label class="text-sm">Model:</label>
            <%= if @models_loading do %>
              <span class="loading loading-spinner loading-sm"></span>
            <% else %>
              <select
                phx-change="select_model"
                name="model"
                class="select select-sm select-bordered"
                disabled={@is_streaming}
              >
                <%= for model <- @available_models do %>
                  <option value={model["id"]} selected={model["id"] == @selected_model}>
                    {model["id"]}
                  </option>
                <% end %>
              </select>
            <% end %>
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

          <%= if @is_streaming and @streaming_message != "" do %>
            <div class="chat chat-start">
              <div class="chat-bubble">
                <div class="whitespace-pre-wrap">{@streaming_message}</div>
                <span class="loading loading-dots loading-sm"></span>
              </div>
            </div>
          <% end %>

          <%= if @is_streaming and @streaming_message == "" do %>
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
    </div>
    """
  end
end
