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
  Database saves are spawned asynchronously for parallel processing.
  """
  @spec handle_progress(
          :markdown_files,
          Phoenix.LiveView.UploadEntry.t(),
          Phoenix.LiveView.Socket.t()
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_progress(:markdown_files, entry, socket) do
    if entry.done? do
      # Upload complete, save to database asynchronously
      conversation = socket.assigns[:current_conversation]

      if conversation && conversation.id do
        socket = save_completed_upload_async(socket, entry, conversation.id)
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
  defp save_completed_upload_async(socket, entry, conversation_id) do
    liveview_pid = self()

    # Track pending save for UI display
    pending_save = %{
      ref: entry.ref,
      filename: entry.client_name,
      size: entry.client_size
    }

    pending_saves = [pending_save | socket.assigns[:pending_saves] || []]

    # Consume the entry synchronously (required by Phoenix) but spawn DB save
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      process_uploaded_file(path, entry, conversation_id, liveview_pid)
    end)

    assign(socket, :pending_saves, pending_saves)
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Path is provided by Phoenix's upload handling - safe temporary file path
  defp process_uploaded_file(path, entry, conversation_id, liveview_pid) do
    case File.read(path) do
      {:ok, content} ->
        spawn_attachment_save(content, entry, conversation_id, liveview_pid)
        {:ok, :spawned}

      {:error, _reason} ->
        send(liveview_pid, {:attachment_saved, {:error, entry.client_name}})
        {:ok, :error}
    end
  end

  defp spawn_attachment_save(content, entry, conversation_id, liveview_pid) do
    attrs = %{
      conversation_id: conversation_id,
      filename: entry.client_name,
      content: content,
      content_type: entry.client_type || "text/markdown",
      size_bytes: entry.client_size
    }

    ref = entry.ref

    Task.Supervisor.start_child(Chatbot.TaskSupervisor, fn ->
      result = save_attachment_to_db(attrs, entry.client_name)
      send(liveview_pid, {:attachment_saved, result, ref})
    end)
  end

  defp save_attachment_to_db(attrs, filename) do
    case Chat.create_attachment(attrs) do
      {:ok, attachment} -> {:ok, attachment}
      {:error, _changeset} -> {:error, filename}
    end
  end

  @doc """
  Handles the result of an async attachment save.
  Call this from your LiveView's handle_info for {:attachment_saved, result, ref}.
  """
  @spec handle_attachment_saved(
          {:ok, ConversationAttachment.t()} | {:error, String.t()},
          String.t(),
          Phoenix.LiveView.Socket.t()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_attachment_saved({:ok, attachment}, ref, socket) do
    # Remove from pending saves and add to attachments
    pending_saves = Enum.reject(socket.assigns[:pending_saves] || [], &(&1.ref == ref))
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    updated_attachments = socket.assigns.attachments ++ [attachment]

    {:noreply,
     socket
     |> assign(:attachments, updated_attachments)
     |> assign(:pending_saves, pending_saves)}
  end

  def handle_attachment_saved({:error, filename}, ref, socket) do
    # Remove from pending saves even on error
    pending_saves = Enum.reject(socket.assigns[:pending_saves] || [], &(&1.ref == ref))

    {:noreply,
     socket
     |> assign(:pending_saves, pending_saves)
     |> put_flash(:error, "Failed to save #{filename}")}
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
