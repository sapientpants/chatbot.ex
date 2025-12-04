defmodule Chatbot.RAG.ChunkProcessor do
  @moduledoc """
  Processes attachments into chunks with embeddings.

  This module handles the synchronous processing of file attachments into
  searchable chunks. It creates chunks using the MarkdownChunker and generates
  embeddings via the ProviderRouter.

  ## Usage

      # Process a single attachment (called after attachment creation)
      {:ok, chunks} = ChunkProcessor.process_attachment(attachment)

      # Reprocess all attachments for a conversation
      {:ok, count} = ChunkProcessor.reprocess_conversation(conversation_id)

      # Delete chunks for an attachment
      {count, _} = ChunkProcessor.delete_chunks_for_attachment(attachment_id)

  """

  import Ecto.Query, only: [where: 3]

  alias Chatbot.Chat.AttachmentChunk
  alias Chatbot.Chat.ConversationAttachment
  alias Chatbot.ProviderRouter
  alias Chatbot.RAG.MarkdownChunker
  alias Chatbot.Repo

  require Logger

  @batch_size 10

  @doc """
  Processes an attachment, creating chunks with embeddings.

  This is called synchronously after attachment creation. The process:
  1. Chunks the attachment content using markdown-aware splitting
  2. Generates embeddings for all chunks (in batches)
  3. Inserts all chunks in a single transaction

  ## Parameters

    * `attachment` - The ConversationAttachment to process

  ## Returns

    * `{:ok, chunks}` - List of created AttachmentChunk structs
    * `{:error, reason}` - If processing fails

  """
  @spec process_attachment(ConversationAttachment.t()) ::
          {:ok, [AttachmentChunk.t()]} | {:error, term()}
  def process_attachment(%ConversationAttachment{} = attachment) do
    Logger.info("Processing attachment #{attachment.id} for chunking")

    with {:ok, raw_chunks} <- chunk_content(attachment),
         {:ok, embedded_chunks} <- embed_chunks(raw_chunks),
         {:ok, saved_chunks} <- save_chunks(embedded_chunks, attachment) do
      Logger.info("Created #{length(saved_chunks)} chunks for attachment #{attachment.id}")
      {:ok, saved_chunks}
    else
      {:error, reason} = error ->
        Logger.error("Failed to process attachment #{attachment.id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Reprocesses all attachments for a conversation.

  Deletes existing chunks and recreates them. Useful for reindexing after
  chunking strategy changes.

  ## Parameters

    * `conversation_id` - The conversation ID

  ## Returns

    * `{:ok, total_chunks}` - Total number of chunks created
    * `{:error, reason}` - If reprocessing fails

  """
  @spec reprocess_conversation(binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def reprocess_conversation(conversation_id) do
    # First delete all existing chunks for this conversation
    delete_chunks_for_conversation(conversation_id)

    # Get all attachments
    attachments =
      ConversationAttachment
      |> where([a], a.conversation_id == ^conversation_id)
      |> Repo.all()

    # Process each attachment
    results =
      Enum.map(attachments, fn attachment ->
        case process_attachment(attachment) do
          {:ok, chunks} -> {:ok, length(chunks)}
          error -> error
        end
      end)

    # Check for errors
    errors = Enum.filter(results, &match?({:error, _reason}, &1))

    if errors == [] do
      total = results |> Enum.map(fn {:ok, count} -> count end) |> Enum.sum()
      {:ok, total}
    else
      {:error, "Some attachments failed to process"}
    end
  end

  @doc """
  Deletes all chunks for a specific attachment.

  Note: This is typically handled automatically by PostgreSQL cascade delete
  when the attachment is deleted. This function is for manual cleanup.

  ## Parameters

    * `attachment_id` - The attachment ID

  ## Returns

    * `{count, nil}` - Number of chunks deleted

  """
  @spec delete_chunks_for_attachment(binary()) :: {non_neg_integer(), nil}
  def delete_chunks_for_attachment(attachment_id) do
    AttachmentChunk
    |> where([c], c.attachment_id == ^attachment_id)
    |> Repo.delete_all()
  end

  @doc """
  Deletes all chunks for a specific conversation.

  ## Parameters

    * `conversation_id` - The conversation ID

  ## Returns

    * `{count, nil}` - Number of chunks deleted

  """
  @spec delete_chunks_for_conversation(binary()) :: {non_neg_integer(), nil}
  def delete_chunks_for_conversation(conversation_id) do
    AttachmentChunk
    |> where([c], c.conversation_id == ^conversation_id)
    |> Repo.delete_all()
  end

  # Private functions

  defp chunk_content(attachment) do
    opts = [filename: attachment.filename]

    chunks = MarkdownChunker.chunk(attachment.content, opts)

    max_chunks = config(:max_chunks_per_attachment, 100)

    if length(chunks) > max_chunks do
      Logger.warning(
        "Attachment #{attachment.id} produced #{length(chunks)} chunks, limiting to #{max_chunks}"
      )

      {:ok, Enum.take(chunks, max_chunks)}
    else
      {:ok, chunks}
    end
  end

  defp embed_chunks(chunks) do
    chunks
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      texts = Enum.map(batch, & &1.content)

      case ProviderRouter.embed_batch(texts) do
        {:ok, embeddings} ->
          embedded =
            batch
            |> Enum.zip(embeddings)
            |> Enum.map(fn {chunk, embedding} ->
              Map.put(chunk, :embedding, embedding)
            end)

          {:cont, {:ok, acc ++ embedded}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp save_chunks(chunks, attachment) do
    now = DateTime.utc_now(:second)

    chunk_records =
      Enum.map(chunks, fn chunk ->
        %{
          id: Repo.generate_uuid(),
          conversation_id: attachment.conversation_id,
          attachment_id: attachment.id,
          content: chunk.content,
          chunk_index: chunk.index,
          embedding: Pgvector.new(chunk.embedding),
          metadata: chunk.metadata,
          content_hash: chunk.content_hash,
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all(AttachmentChunk, chunk_records, returning: true) do
      {count, inserted_chunks} when count > 0 ->
        {:ok, inserted_chunks}

      {0, _empty} ->
        {:ok, []}

      error ->
        {:error, error}
    end
  end

  defp config(key, default) do
    rag_config = Application.get_env(:chatbot, :rag, [])
    Keyword.get(rag_config, key, default)
  end
end
