defmodule Chatbot.Chat.ConversationAttachmentTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Chat.ConversationAttachment
  import Chatbot.Fixtures

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        filename: "test.md",
        content: "# Test content",
        size_bytes: 100
      }

      changeset = ConversationAttachment.changeset(%ConversationAttachment{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = ConversationAttachment.changeset(%ConversationAttachment{}, %{})
      refute changeset.valid?
      assert errors_on(changeset)[:filename]
      assert errors_on(changeset)[:content]
      assert errors_on(changeset)[:size_bytes]
      assert errors_on(changeset)[:conversation_id]
    end

    test "rejects files exceeding max size" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        filename: "large.md",
        content: String.duplicate("x", 200_000),
        size_bytes: 200_000
      }

      changeset = ConversationAttachment.changeset(%ConversationAttachment{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:size_bytes]
    end

    test "rejects non-markdown file extensions" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        filename: "script.js",
        content: "console.log('test')",
        size_bytes: 20
      }

      changeset = ConversationAttachment.changeset(%ConversationAttachment{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:filename]
    end

    test "accepts .md extension" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        filename: "notes.md",
        content: "# Notes",
        size_bytes: 10
      }

      changeset = ConversationAttachment.changeset(%ConversationAttachment{}, attrs)
      assert changeset.valid?
    end

    test "accepts .markdown extension" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        filename: "readme.markdown",
        content: "# Readme",
        size_bytes: 10
      }

      changeset = ConversationAttachment.changeset(%ConversationAttachment{}, attrs)
      assert changeset.valid?
    end

    test "accepts .txt extension" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        filename: "notes.txt",
        content: "Some notes",
        size_bytes: 10
      }

      changeset = ConversationAttachment.changeset(%ConversationAttachment{}, attrs)
      assert changeset.valid?
    end

    test "validates filename max length" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        filename: String.duplicate("a", 256) <> ".md",
        content: "# Test",
        size_bytes: 10
      }

      changeset = ConversationAttachment.changeset(%ConversationAttachment{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:filename]
    end
  end

  describe "constants" do
    test "max_file_size returns 100KB" do
      assert ConversationAttachment.max_file_size() == 100 * 1024
    end

    test "max_attachments_per_conversation returns 5" do
      assert ConversationAttachment.max_attachments_per_conversation() == 5
    end

    test "allowed_extensions returns expected list" do
      assert ConversationAttachment.allowed_extensions() == ~w(.md .markdown .txt)
    end
  end
end
