defmodule ChatbotWeb.ChatLive.Show do
  use ChatbotWeb, :live_view

  alias Chatbot.Chat
  alias Chatbot.LMStudio

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_user.id
    conversation = Chat.get_conversation_with_messages!(id)

    # Verify the conversation belongs to the current user
    if conversation.user_id != user_id do
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
        |> assign(:streaming_message, "")
        |> assign(:is_streaming, false)
        |> assign(:available_models, [])
        |> assign(:selected_model, conversation.model_name)
        |> assign(:models_loading, true)
        |> assign(:show_delete_modal, false)
        |> assign(:form, to_form(%{"content" => ""}, as: :message))

      # Load available models asynchronously
      send(self(), :load_models)

      {:ok, socket}
    end
  end

  @impl true
  def handle_info(:load_models, socket) do
    case LMStudio.list_models() do
      {:ok, models} ->
        selected_model =
          socket.assigns.selected_model || if(length(models) > 0, do: hd(models)["id"], else: nil)

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
    assistant_message = socket.assigns.streaming_message

    {:ok, _message} =
      Chat.create_message(%{
        conversation_id: conversation_id,
        role: "assistant",
        content: assistant_message
      })

    # Reload messages
    conversation = Chat.get_conversation_with_messages!(conversation_id)

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

      # Save user message
      {:ok, _message} =
        Chat.create_message(%{
          conversation_id: conversation_id,
          role: "user",
          content: content
        })

      # Reload conversation with messages
      conversation = Chat.get_conversation_with_messages!(conversation_id)
      messages = conversation.messages

      # Build OpenAI format messages
      openai_messages = Chat.build_openai_messages(messages)

      # Start streaming response from LM Studio
      model = socket.assigns.selected_model || "default"

      # Update conversation model if changed
      socket =
        if socket.assigns.current_conversation.model_name != model do
          {:ok, updated_conv} =
            Chat.update_conversation(socket.assigns.current_conversation, %{model_name: model})

          assign(socket, :current_conversation, updated_conv)
        else
          socket
        end

      # Capture LiveView PID before starting Task
      liveview_pid = self()

      Task.start(fn ->
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
  def handle_event("show_delete_modal", _, socket) do
    {:noreply, assign(socket, :show_delete_modal, true)}
  end

  @impl true
  def handle_event("hide_delete_modal", _, socket) do
    {:noreply, assign(socket, :show_delete_modal, false)}
  end

  @impl true
  def handle_event("confirm_delete_conversation", _, socket) do
    case Chat.delete_conversation(socket.assigns.current_conversation) do
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
      messages
      |> Enum.map(fn msg ->
        role_label = if msg.role == "user", do: "**You:**", else: "**Assistant:**"

        """
        #{role_label}

        #{msg.content}

        """
      end)
      |> Enum.join("\n---\n\n")

    header <> messages_md
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
        <!-- Header with model selection and actions -->
        <div class="bg-base-100 border-b border-base-300 p-4 flex items-center justify-between">
          <h2 class="text-xl font-bold">{@current_conversation.title || "New Conversation"}</h2>

          <div class="flex items-center gap-4">
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

            <div class="dropdown dropdown-end">
              <label tabindex="0" class="btn btn-sm btn-ghost">
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
