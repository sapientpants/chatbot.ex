defmodule Chatbot.ChatTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Chat
  alias Chatbot.Chat.Conversation
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

  describe "get_conversation!/1" do
    test "returns the conversation with given id" do
      conversation = conversation_fixture()
      fetched = Chat.get_conversation!(conversation.id)
      assert fetched.id == conversation.id
      assert fetched.title == conversation.title
    end

    test "raises when conversation does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation!("00000000-0000-0000-0000-000000000000")
      end
    end
  end

  describe "get_conversation_with_messages!/1" do
    test "returns conversation with messages preloaded in order" do
      conversation = conversation_fixture()
      message1 = message_fixture(conversation: conversation, content: "First")
      # Ensure different timestamps
      Process.sleep(10)
      message2 = message_fixture(conversation: conversation, content: "Second")

      fetched = Chat.get_conversation_with_messages!(conversation.id)
      assert fetched.id == conversation.id
      assert length(fetched.messages) == 2
      assert [message1.id, message2.id] == Enum.map(fetched.messages, & &1.id)
    end

    test "raises when conversation does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation_with_messages!("00000000-0000-0000-0000-000000000000")
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

  describe "delete_conversation/1" do
    test "deletes the conversation" do
      conversation = conversation_fixture()
      assert {:ok, %Conversation{}} = Chat.delete_conversation(conversation)
      assert_raise Ecto.NoResultsError, fn -> Chat.get_conversation!(conversation.id) end
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
end
