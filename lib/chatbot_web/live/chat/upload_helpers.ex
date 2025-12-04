defmodule ChatbotWeb.Live.Chat.UploadHelpers do
  @moduledoc """
  Shared helpers for handling markdown file uploads in chat LiveViews.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias Chatbot.Chat
  alias Chatbot.Chat.ConversationAttachment

  # Maximum concurrent database saves to prevent overwhelming the server
  @max_concurrent_saves 5

  @doc """
  Initializes all upload-related assigns on a socket.
  Call this in mount to set up pending_saves, saves_in_flight, save_queue, and attachments_expanded.
  """
  @spec init_upload_assigns(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init_upload_assigns(socket) do
    socket
    |> assign(:attachments_expanded, false)
    |> assign(:pending_saves, [])
    |> assign(:saves_in_flight, 0)
    |> assign(:save_queue, [])
  end

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
        # No conversation - consume and discard the upload
        consume_uploaded_entry(socket, entry, fn _meta -> {:ok, :discarded} end)
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

    # Consume the entry and read content immediately (before temp file is deleted)
    # consume_uploaded_entry callback MUST return {:ok, value} - wrap errors
    # sobelow_skip ["Traversal.FileModule"]
    save_result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        case File.read(path) do
          {:ok, content} ->
            {:ok,
             {:ok,
              %{
                attrs: %{
                  conversation_id: conversation_id,
                  filename: entry.client_name,
                  content: content,
                  content_type: entry.client_type || "text/markdown",
                  size_bytes: entry.client_size
                },
                ref: entry.ref,
                filename: entry.client_name
              }}}

          {:error, _reason} ->
            {:ok, {:error, entry.client_name}}
        end
      end)

    socket = assign(socket, :pending_saves, pending_saves)

    # Either spawn immediately or queue based on current load
    case save_result do
      {:ok, item} ->
        maybe_spawn_or_queue(socket, item, liveview_pid)

      {:error, filename} ->
        send(liveview_pid, {:attachment_saved, {:error, filename}, entry.ref})
        socket
    end
  end

  defp maybe_spawn_or_queue(socket, item, liveview_pid) do
    saves_in_flight = socket.assigns[:saves_in_flight] || 0
    save_queue = socket.assigns[:save_queue] || []

    if saves_in_flight < @max_concurrent_saves do
      # Spawn immediately
      spawn_attachment_save(item, liveview_pid)
      assign(socket, :saves_in_flight, saves_in_flight + 1)
    else
      # Queue for later - order matters so we reverse at the end
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      assign(socket, :save_queue, save_queue ++ [item])
    end
  end

  defp spawn_attachment_save(item, liveview_pid) do
    %{attrs: attrs, ref: ref, filename: filename} = item

    Task.Supervisor.start_child(Chatbot.TaskSupervisor, fn ->
      result =
        try do
          save_attachment_to_db(attrs, filename)
        rescue
          _exception ->
            {:error, filename}
        end

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

    socket =
      socket
      |> assign(:attachments, updated_attachments)
      |> assign(:pending_saves, pending_saves)
      |> process_save_queue()

    {:noreply, socket}
  end

  def handle_attachment_saved({:error, filename}, ref, socket) do
    # Remove from pending saves even on error
    pending_saves = Enum.reject(socket.assigns[:pending_saves] || [], &(&1.ref == ref))

    socket =
      socket
      |> assign(:pending_saves, pending_saves)
      |> put_flash(:error, "Failed to save #{filename}")
      |> process_save_queue()

    {:noreply, socket}
  end

  # Process the next item from the queue when a save completes
  defp process_save_queue(socket) do
    saves_in_flight = max((socket.assigns[:saves_in_flight] || 1) - 1, 0)
    save_queue = socket.assigns[:save_queue] || []

    case save_queue do
      [next_item | rest] ->
        # Spawn next item and keep saves_in_flight the same (one finished, one started)
        spawn_attachment_save(next_item, self())

        socket
        |> assign(:saves_in_flight, saves_in_flight + 1)
        |> assign(:save_queue, rest)

      [] ->
        # Nothing queued, just decrement counter
        assign(socket, :saves_in_flight, saves_in_flight)
    end
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
