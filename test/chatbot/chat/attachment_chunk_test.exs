defmodule Chatbot.Chat.AttachmentChunkTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Chat.AttachmentChunk

  import Chatbot.Fixtures

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attachment = attachment_fixture_without_chunks()

      attrs = %{
        conversation_id: attachment.conversation_id,
        attachment_id: attachment.id,
        content: "Test chunk content",
        chunk_index: 0
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      assert changeset.valid?
    end

    test "generates UUID if not provided" do
      attachment = attachment_fixture_without_chunks()

      attrs = %{
        conversation_id: attachment.conversation_id,
        attachment_id: attachment.id,
        content: "Test chunk content",
        chunk_index: 0
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :id) != nil
    end

    test "computes content_hash from content" do
      attachment = attachment_fixture_without_chunks()

      attrs = %{
        conversation_id: attachment.conversation_id,
        attachment_id: attachment.id,
        content: "Test chunk content",
        chunk_index: 0
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      content_hash = Ecto.Changeset.get_change(changeset, :content_hash)
      assert content_hash != nil
      # SHA256 hex
      assert String.length(content_hash) == 64
    end

    test "invalid without content" do
      attachment = attachment_fixture_without_chunks()

      attrs = %{
        conversation_id: attachment.conversation_id,
        attachment_id: attachment.id,
        chunk_index: 0
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).content
    end

    test "invalid without chunk_index" do
      attachment = attachment_fixture_without_chunks()

      attrs = %{
        conversation_id: attachment.conversation_id,
        attachment_id: attachment.id,
        content: "Test content"
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).chunk_index
    end

    test "invalid with negative chunk_index" do
      attachment = attachment_fixture_without_chunks()

      attrs = %{
        conversation_id: attachment.conversation_id,
        attachment_id: attachment.id,
        content: "Test content",
        chunk_index: -1
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).chunk_index
    end

    test "invalid without conversation_id" do
      attachment = attachment_fixture_without_chunks()

      attrs = %{
        attachment_id: attachment.id,
        content: "Test content",
        chunk_index: 0
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).conversation_id
    end

    test "invalid without attachment_id" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        content: "Test content",
        chunk_index: 0
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).attachment_id
    end

    test "accepts embedding vector" do
      attachment = attachment_fixture_without_chunks()
      embedding = List.duplicate(0.1, 1024)

      attrs = %{
        conversation_id: attachment.conversation_id,
        attachment_id: attachment.id,
        content: "Test content",
        chunk_index: 0,
        embedding: embedding
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      assert changeset.valid?
    end

    test "accepts metadata map" do
      attachment = attachment_fixture_without_chunks()

      attrs = %{
        conversation_id: attachment.conversation_id,
        attachment_id: attachment.id,
        content: "Test content",
        chunk_index: 0,
        metadata: %{headers: ["Section 1"], section_path: "Section 1", start_line: 1}
      }

      changeset = AttachmentChunk.changeset(%AttachmentChunk{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :metadata) == attrs.metadata
    end
  end

  describe "database operations" do
    test "can insert a chunk" do
      chunk = attachment_chunk_fixture()

      assert chunk.id != nil
      assert chunk.content != nil
      assert chunk.content_hash != nil
    end

    test "cascade deletes when attachment is deleted" do
      attachment = attachment_fixture_without_chunks()
      chunk = attachment_chunk_fixture(attachment: attachment)

      # Verify chunk exists
      assert Repo.get(AttachmentChunk, chunk.id) != nil

      # Delete attachment
      Repo.delete!(attachment)

      # Chunk should be cascade deleted
      assert Repo.get(AttachmentChunk, chunk.id) == nil
    end

    test "cascade deletes when conversation is deleted" do
      conversation = conversation_fixture()
      attachment = attachment_fixture_without_chunks(conversation: conversation)
      chunk = attachment_chunk_fixture(attachment: attachment)

      # Verify chunk exists
      assert Repo.get(AttachmentChunk, chunk.id) != nil

      # Delete conversation
      Repo.delete!(conversation)

      # Chunk should be cascade deleted
      assert Repo.get(AttachmentChunk, chunk.id) == nil
    end
  end
end
