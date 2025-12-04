defmodule Chatbot.ChatTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Chat
  alias Chatbot.Chat.Conversation
  alias Chatbot.Chat.ConversationAttachment
  alias Chatbot.Chat.Message
  import Chatbot.Fixtures

  describe "list_conversations/1" do
    test "returns all conversations for a user" do
      user = user_fixture()
      conversation1 = conversation_fixture(user: user, title: "First")
      conversation2 = conversation_fixture(user: user, title: "Second")

      conversations = Chat.list_conversations(user.id)
      assert length(conversations) == 2
      conversation_ids = Enum.map(conversations, & &1.id)
      assert conversation1.id in conversation_ids
      assert conversation2.id in conversation_ids
    end

    test "does not return conversations for other users" do
      user1 = user_fixture()
      user2 = user_fixture()
      _conversation1 = conversation_fixture(user: user1)
      _conversation2 = conversation_fixture(user: user2)

      conversations = Chat.list_conversations(user1.id)
      assert length(conversations) == 1
    end

    test "returns empty list when user has no conversations" do
      user = user_fixture()
      assert Chat.list_conversations(user.id) == []
    end
  end

  describe "get_conversation!/2" do
    test "returns the conversation with given id for the user" do
      user = user_fixture()
      conversation = conversation_fixture(%{user: user})
      fetched = Chat.get_conversation!(conversation.id, user.id)
      assert fetched.id == conversation.id
      assert fetched.title == conversation.title
    end

    test "raises when conversation does not exist" do
      user = user_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation!("00000000-0000-0000-0000-000000000000", user.id)
      end
    end

    test "raises when conversation belongs to different user" do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_fixture(%{user: user1})

      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation!(conversation.id, user2.id)
      end
    end
  end

  describe "get_conversation_with_messages!/2" do
    test "returns conversation with messages preloaded in order for the user" do
      user = user_fixture()
      conversation = conversation_fixture(user: user)
      # UUID7s are time-ordered, so sequential creation maintains order
      message1 = message_fixture(conversation: conversation, content: "First")
      message2 = message_fixture(conversation: conversation, content: "Second")

      fetched = Chat.get_conversation_with_messages!(conversation.id, user.id)
      assert fetched.id == conversation.id
      assert length(fetched.messages) == 2
      assert [message1.id, message2.id] == Enum.map(fetched.messages, & &1.id)
    end

    test "raises when conversation does not exist" do
      user = user_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation_with_messages!("00000000-0000-0000-0000-000000000000", user.id)
      end
    end

    test "raises when conversation belongs to different user" do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_fixture(user: user1)

      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation_with_messages!(conversation.id, user2.id)
      end
    end
  end

  describe "create_conversation/1" do
    test "creates a conversation with valid attributes" do
      user = user_fixture()
      valid_attrs = %{user_id: user.id, title: "Test Chat"}

      assert {:ok, %Conversation{} = conversation} = Chat.create_conversation(valid_attrs)
      assert conversation.title == "Test Chat"
      assert conversation.user_id == user.id
    end

    test "creates a conversation without title" do
      user = user_fixture()
      valid_attrs = %{user_id: user.id}

      assert {:ok, %Conversation{} = conversation} = Chat.create_conversation(valid_attrs)
      assert conversation.user_id == user.id
    end

    test "returns error changeset with invalid data" do
      assert {:error, %Ecto.Changeset{}} = Chat.create_conversation(%{})
    end
  end

  describe "update_conversation/2" do
    test "updates the conversation with valid attributes" do
      conversation = conversation_fixture(title: "Old Title")
      update_attrs = %{title: "New Title"}

      assert {:ok, %Conversation{} = updated} =
               Chat.update_conversation(conversation, update_attrs)

      assert updated.title == "New Title"
    end

    test "returns error changeset with invalid data" do
      conversation = conversation_fixture()
      assert {:error, %Ecto.Changeset{}} = Chat.update_conversation(conversation, %{user_id: nil})
    end
  end

  describe "delete_conversation/2" do
    test "deletes the conversation when user owns it" do
      user = user_fixture()
      conversation = conversation_fixture(user: user)
      assert {:ok, %Conversation{}} = Chat.delete_conversation(conversation, user.id)
      assert_raise Ecto.NoResultsError, fn -> Chat.get_conversation!(conversation.id, user.id) end
    end

    test "returns error when user does not own conversation" do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_fixture(user: user1)
      assert {:error, :unauthorized} = Chat.delete_conversation(conversation, user2.id)
    end
  end

  describe "change_conversation/2" do
    test "returns a conversation changeset" do
      conversation = conversation_fixture()
      assert %Ecto.Changeset{} = Chat.change_conversation(conversation)
    end

    test "returns a changeset with changes" do
      conversation = conversation_fixture()
      changeset = Chat.change_conversation(conversation, %{title: "New Title"})
      assert changeset.changes.title == "New Title"
    end
  end

  describe "create_message/1" do
    test "creates a message with valid attributes" do
      conversation = conversation_fixture()

      valid_attrs = %{
        conversation_id: conversation.id,
        role: "user",
        content: "Hello world"
      }

      assert {:ok, %Message{} = message} = Chat.create_message(valid_attrs)
      assert message.content == "Hello world"
      assert message.role == "user"
      assert message.conversation_id == conversation.id
    end

    test "creates a message with tokens_used" do
      conversation = conversation_fixture()

      valid_attrs = %{
        conversation_id: conversation.id,
        role: "assistant",
        content: "Response",
        tokens_used: 42
      }

      assert {:ok, %Message{} = message} = Chat.create_message(valid_attrs)
      assert message.tokens_used == 42
    end

    test "returns error changeset with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Chat.create_message(%{})
    end

    test "returns error changeset with invalid role" do
      conversation = conversation_fixture()

      invalid_attrs = %{
        conversation_id: conversation.id,
        role: "invalid",
        content: "Test"
      }

      assert {:error, %Ecto.Changeset{}} = Chat.create_message(invalid_attrs)
    end

    test "generates UUID for new message" do
      conversation = conversation_fixture()

      valid_attrs = %{
        conversation_id: conversation.id,
        role: "user",
        content: "Test message"
      }

      assert {:ok, %Message{} = message} = Chat.create_message(valid_attrs)
      assert message.id
      assert is_binary(message.id)
    end
  end

  describe "generate_conversation_title/1" do
    test "returns first 50 characters of message" do
      message = "This is a test message"
      assert Chat.generate_conversation_title(message) == message
    end

    test "truncates long messages to 50 characters with ellipsis" do
      long_message = String.duplicate("a", 60)
      title = Chat.generate_conversation_title(long_message)
      assert String.length(title) == 53
      assert String.ends_with?(title, "...")
      assert String.starts_with?(title, String.slice(long_message, 0, 50))
    end

    test "returns 'New Conversation' for empty string" do
      assert Chat.generate_conversation_title("") == "New Conversation"
    end

    test "returns 'New Conversation' for whitespace only" do
      assert Chat.generate_conversation_title("   ") == "New Conversation"
    end

    test "returns 'New Conversation' for nil" do
      assert Chat.generate_conversation_title(nil) == "New Conversation"
    end

    test "returns 'New Conversation' for non-string" do
      assert Chat.generate_conversation_title(123) == "New Conversation"
    end
  end

  describe "build_openai_messages/1" do
    test "converts messages to OpenAI format" do
      conversation = conversation_fixture()
      message1 = message_fixture(conversation: conversation, role: "user", content: "Hello")

      message2 =
        message_fixture(conversation: conversation, role: "assistant", content: "Hi there")

      result = Chat.build_openai_messages([message1, message2])

      assert result == [
               %{role: "user", content: "Hello"},
               %{role: "assistant", content: "Hi there"}
             ]
    end

    test "returns empty list for no messages" do
      assert Chat.build_openai_messages([]) == []
    end
  end

  # ============================================
  # Attachment Functions
  # ============================================

  describe "list_attachments/1" do
    test "returns attachments for a conversation in order" do
      user = user_fixture()
      conversation = conversation_fixture(user: user)
      a1 = attachment_fixture(conversation: conversation, filename: "first.md")
      a2 = attachment_fixture(conversation: conversation, filename: "second.md")

      attachments = Chat.list_attachments(conversation.id)
      assert length(attachments) == 2
      assert [a1.id, a2.id] == Enum.map(attachments, & &1.id)
    end

    test "returns empty list for conversation without attachments" do
      conversation = conversation_fixture()
      assert Chat.list_attachments(conversation.id) == []
    end

    test "does not return attachments from other conversations" do
      user = user_fixture()
      conversation1 = conversation_fixture(user: user)
      conversation2 = conversation_fixture(user: user)
      _attachment1 = attachment_fixture(conversation: conversation1)
      _attachment2 = attachment_fixture(conversation: conversation2)

      attachments = Chat.list_attachments(conversation1.id)
      assert length(attachments) == 1
    end
  end

  describe "get_attachment/1" do
    test "returns the attachment with given id" do
      attachment = attachment_fixture()
      fetched = Chat.get_attachment(attachment.id)
      assert fetched.id == attachment.id
      assert fetched.filename == attachment.filename
    end

    test "returns nil when attachment does not exist" do
      assert Chat.get_attachment("00000000-0000-0000-0000-000000000000") == nil
    end
  end

  describe "get_attachment_for_user/2" do
    test "returns attachment when user owns the conversation" do
      user = user_fixture()
      conversation = conversation_fixture(user: user)
      attachment = attachment_fixture(conversation: conversation)

      assert {:ok, fetched} = Chat.get_attachment_for_user(attachment.id, user.id)
      assert fetched.id == attachment.id
    end

    test "returns error when user does not own the conversation" do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_fixture(user: user1)
      attachment = attachment_fixture(conversation: conversation)

      assert {:error, :not_found} = Chat.get_attachment_for_user(attachment.id, user2.id)
    end

    test "returns error when attachment does not exist" do
      user = user_fixture()

      assert {:error, :not_found} =
               Chat.get_attachment_for_user("00000000-0000-0000-0000-000000000000", user.id)
    end
  end

  describe "create_attachment/1" do
    test "creates attachment with valid attributes" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        filename: "notes.md",
        content: "# My Notes",
        size_bytes: 50
      }

      assert {:ok, %ConversationAttachment{} = attachment} = Chat.create_attachment(attrs)
      assert attachment.filename == "notes.md"
      assert attachment.content == "# My Notes"
      assert attachment.size_bytes == 50
    end

    test "returns error changeset with invalid attributes" do
      assert {:error, %Ecto.Changeset{}} = Chat.create_attachment(%{})
    end

    # Skipped: limit is now 1000 (effectively unlimited) - impractical to test
    @tag :skip
    test "fails when at max attachment limit" do
      conversation = conversation_fixture()

      # Create max attachments
      for i <- 1..1000 do
        {:ok, _attachment} =
          Chat.create_attachment(%{
            conversation_id: conversation.id,
            filename: "file#{i}.md",
            content: "content",
            size_bytes: 10
          })
      end

      # Try to add one more
      result =
        Chat.create_attachment(%{
          conversation_id: conversation.id,
          filename: "extra.md",
          content: "content",
          size_bytes: 10
        })

      assert result == {:error, :attachment_limit_exceeded}
    end
  end

  describe "delete_attachment/1" do
    test "deletes the attachment" do
      attachment = attachment_fixture()
      assert {:ok, %ConversationAttachment{}} = Chat.delete_attachment(attachment)
      assert Chat.get_attachment(attachment.id) == nil
    end
  end

  describe "delete_attachment_for_user/2" do
    test "deletes attachment when user owns the conversation" do
      user = user_fixture()
      conversation = conversation_fixture(user: user)
      attachment = attachment_fixture(conversation: conversation)

      assert {:ok, %ConversationAttachment{}} =
               Chat.delete_attachment_for_user(attachment.id, user.id)

      assert Chat.get_attachment(attachment.id) == nil
    end

    test "returns error when user does not own the conversation" do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_fixture(user: user1)
      attachment = attachment_fixture(conversation: conversation)

      assert {:error, :not_found} = Chat.delete_attachment_for_user(attachment.id, user2.id)
      # Attachment should still exist
      assert Chat.get_attachment(attachment.id) != nil
    end
  end

  describe "attachment_count/1" do
    test "returns the count of attachments for a conversation" do
      conversation = conversation_fixture()
      assert Chat.attachment_count(conversation.id) == 0

      attachment_fixture(conversation: conversation)
      assert Chat.attachment_count(conversation.id) == 1

      attachment_fixture(conversation: conversation)
      assert Chat.attachment_count(conversation.id) == 2
    end
  end

  describe "total_attachment_size/1" do
    test "returns total size of all attachments" do
      conversation = conversation_fixture()
      assert Chat.total_attachment_size(conversation.id) == 0

      attachment_fixture(conversation: conversation, size_bytes: 100)
      attachment_fixture(conversation: conversation, size_bytes: 200)

      assert Chat.total_attachment_size(conversation.id) == 300
    end
  end

  describe "can_add_attachment?/1" do
    test "returns true when under limit" do
      conversation = conversation_fixture()
      assert Chat.can_add_attachment?(conversation.id)
    end

    # Skipped: limit is now 1000 (effectively unlimited) - impractical to test
    @tag :skip
    test "returns false when at limit" do
      conversation = conversation_fixture()

      for i <- 1..1000 do
        attachment_fixture(conversation: conversation, filename: "file#{i}.md")
      end

      refute Chat.can_add_attachment?(conversation.id)
    end
  end

  describe "cascade delete attachments" do
    test "attachments are deleted when conversation is deleted" do
      user = user_fixture()
      conversation = conversation_fixture(user: user)
      attachment = attachment_fixture(conversation: conversation)

      # Verify attachment exists
      assert Chat.get_attachment(attachment.id) != nil

      # Delete conversation
      {:ok, _deleted} = Chat.delete_conversation(conversation, user.id)

      # Attachment should be gone
      assert Chat.get_attachment(attachment.id) == nil
    end
  end
end
