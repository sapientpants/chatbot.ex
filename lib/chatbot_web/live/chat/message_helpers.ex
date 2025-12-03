defmodule ChatbotWeb.Live.Chat.MessageHelpers do
  @moduledoc """
  Shared helpers for message handling in chat LiveViews.

  Provides common functionality for saving messages, extracting facts,
  and updating conversation state.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Chatbot.Chat
  alias Chatbot.Memory.FactExtractor

  @doc """
  Saves an assistant message and updates conversation state.

  Options:
    * `:rag_sources` - List of RAG source metadata for clickable footnotes
  """
  @spec save_assistant_message(
          Phoenix.LiveView.Socket.t(),
          any(),
          String.t(),
          (Phoenix.LiveView.Socket.t() -> Phoenix.LiveView.Socket.t()),
          keyword()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def save_assistant_message(socket, conversation_id, message_content, reset_fn, opts \\ []) do
    rag_sources = Keyword.get(opts, :rag_sources, [])

    case Chat.create_message(%{
           conversation_id: conversation_id,
           role: "assistant",
           content: message_content,
           rag_sources: rag_sources
         }) do
      {:ok, message} ->
        current_conv = socket.assigns.current_conversation
        updated_conv = %{current_conv | updated_at: DateTime.utc_now()}
        conversations = update_conversation_in_list(socket.assigns.conversations, updated_conv)

        maybe_extract_facts(socket, message_content, message.id)

        {:noreply,
         socket
         |> stream_insert(:messages, message, at: -1)
         |> assign(:current_conversation, updated_conv)
         |> assign(:conversations, conversations)
         |> reset_fn.()
         |> assign(:last_user_message, nil)
         |> assign(:form, to_form(%{"content" => ""}, as: :message))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to save assistant message")
         |> reset_fn.()}
    end
  end

  @doc """
  Extracts facts from the conversation exchange asynchronously.
  """
  @spec maybe_extract_facts(Phoenix.LiveView.Socket.t(), String.t(), any()) :: :ok
  def maybe_extract_facts(socket, complete_message, message_id) do
    user_id = socket.assigns.current_user.id
    user_message_content = socket.assigns[:last_user_message] || ""
    model = socket.assigns.selected_model || "default"

    if user_message_content != "" do
      Task.Supervisor.start_child(Chatbot.TaskSupervisor, fn ->
        FactExtractor.extract_and_store(
          user_id,
          user_message_content,
          complete_message,
          message_id,
          model
        )
      end)
    end

    :ok
  end

  @doc """
  Updates a conversation in a list by ID.
  """
  @spec update_conversation_in_list([map()], map()) :: [map()]
  def update_conversation_in_list(conversations, updated_conversation) do
    Enum.map(conversations, fn conv ->
      if conv.id == updated_conversation.id, do: updated_conversation, else: conv
    end)
  end
end
