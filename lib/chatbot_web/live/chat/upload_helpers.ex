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
      auto_upload: false
    )
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
  Handles the upload event, consuming entries and saving to database.
  """
  @spec handle_upload(Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, Phoenix.LiveView.Socket.t(), String.t()}
  def handle_upload(socket) do
    conversation = socket.assigns[:current_conversation]

    if conversation && conversation.id do
      do_handle_upload(socket, conversation.id)
    else
      {:error, socket, "No conversation selected"}
    end
  end

  defp do_handle_upload(socket, conversation_id) do
    current_count = Chat.attachment_count(conversation_id)
    pending_count = length(socket.assigns.uploads.markdown_files.entries)
    max_count = ConversationAttachment.max_attachments_per_conversation()

    if current_count + pending_count > max_count do
      {:error, socket, "Maximum #{max_count} attachments per conversation"}
    else
      results =
        consume_uploaded_entries(socket, :markdown_files, fn %{path: path}, entry ->
          process_upload_entry(path, entry, conversation_id)
        end)

      build_upload_result(socket, results)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Path is provided by Phoenix's upload handling - safe temporary file path
  defp process_upload_entry(path, entry, conversation_id) do
    case File.read(path) do
      {:ok, content} ->
        save_attachment(content, entry, conversation_id)

      {:error, _reason} ->
        {:ok, {:error, entry.client_name}}
    end
  end

  defp save_attachment(content, entry, conversation_id) do
    attrs = %{
      conversation_id: conversation_id,
      filename: entry.client_name,
      content: content,
      content_type: entry.client_type || "text/markdown",
      size_bytes: entry.client_size
    }

    case Chat.create_attachment(attrs) do
      {:ok, attachment} -> {:ok, {:ok, attachment}}
      {:error, _changeset} -> {:ok, {:error, entry.client_name}}
    end
  end

  defp build_upload_result(socket, results) do
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _attachment} -> true
        {:error, _name} -> false
      end)

    uploaded_attachments = Enum.map(successes, fn {:ok, attachment} -> attachment end)

    updated_socket =
      assign(socket, :attachments, socket.assigns.attachments ++ uploaded_attachments)

    if failures == [] do
      {:ok, updated_socket}
    else
      failed_names = Enum.map_join(failures, ", ", fn {:error, name} -> name end)
      {:error, updated_socket, "Failed to upload: #{failed_names}"}
    end
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
