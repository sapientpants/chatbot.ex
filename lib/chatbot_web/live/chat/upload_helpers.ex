defmodule ChatbotWeb.Live.Chat.UploadHelpers do
  @moduledoc """
  Shared helpers for handling markdown file uploads in chat LiveViews.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias Chatbot.Chat
  alias Chatbot.Chat.ConversationAttachment

  @doc """
  Configures file upload for markdown files on a socket.
  """
  @spec configure_uploads(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def configure_uploads(socket) do
    allow_upload(socket, :markdown_files,
      accept: ~w(.md .markdown .txt),
      max_entries: ConversationAttachment.max_attachments_per_conversation(),
      max_file_size: ConversationAttachment.max_file_size(),
      auto_upload: true,
      progress: &handle_progress/3
    )
  end

  @doc """
  Handles upload progress. When an entry completes (100%), saves it to the database.
  """
  @spec handle_progress(
          :markdown_files,
          Phoenix.LiveView.UploadEntry.t(),
          Phoenix.LiveView.Socket.t()
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_progress(:markdown_files, entry, socket) do
    if entry.done? do
      # Upload complete, save to database
      conversation = socket.assigns[:current_conversation]

      if conversation && conversation.id do
        socket = save_completed_upload(socket, entry, conversation.id)
        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Path is provided by Phoenix's upload handling - safe temporary file path
  defp save_completed_upload(socket, entry, conversation_id) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        case File.read(path) do
          {:ok, content} ->
            attrs = %{
              conversation_id: conversation_id,
              filename: entry.client_name,
              content: content,
              content_type: entry.client_type || "text/markdown",
              size_bytes: entry.client_size
            }

            case Chat.create_attachment(attrs) do
              {:ok, attachment} ->
                {:ok, {:ok, attachment}}

              {:error, _changeset} ->
                {:ok, {:error, entry.client_name}}
            end

          {:error, _reason} ->
            {:ok, {:error, entry.client_name}}
        end
      end)

    handle_save_result(result, socket, entry.client_name)
  end

  defp handle_save_result({:ok, attachment}, socket, _filename) do
    # Append to maintain chronological order (newest last)
    # Performance is acceptable for max 1000 attachments added one at a time
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    updated_attachments = socket.assigns.attachments ++ [attachment]
    assign(socket, :attachments, updated_attachments)
  end

  defp handle_save_result({:error, _filename}, socket, filename) do
    put_flash(socket, :error, "Failed to save #{filename}")
  end

  @doc """
  Loads attachments for the current conversation into socket assigns.
  """
  @spec load_attachments(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_attachments(socket) do
    conversation = socket.assigns[:current_conversation]

    attachments =
      if conversation && conversation.id do
        Chat.list_attachments(conversation.id)
      else
        []
      end

    assign(socket, :attachments, attachments)
  end

  @doc """
  Handles canceling an upload entry.
  """
  @spec cancel_upload_entry(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def cancel_upload_entry(socket, ref) do
    cancel_upload(socket, :markdown_files, ref)
  end

  @doc """
  Handles removing an existing attachment.
  """
  @spec remove_attachment(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, Phoenix.LiveView.Socket.t(), String.t()}
  def remove_attachment(socket, attachment_id) do
    user_id = socket.assigns.current_user.id

    case Chat.delete_attachment_for_user(attachment_id, user_id) do
      {:ok, _deleted} ->
        attachments = Enum.reject(socket.assigns.attachments, &(&1.id == attachment_id))
        {:ok, assign(socket, :attachments, attachments)}

      {:error, :not_found} ->
        {:error, socket, "Attachment not found"}

      {:error, _changeset} ->
        {:error, socket, "Failed to remove attachment"}
    end
  end

  @doc """
  Cancels all pending file uploads.
  """
  @spec cancel_pending_uploads(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def cancel_pending_uploads(socket) do
    Enum.reduce(socket.assigns.uploads.markdown_files.entries, socket, fn entry, acc ->
      cancel_upload(acc, :markdown_files, entry.ref)
    end)
  end
end
