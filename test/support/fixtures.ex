defmodule Chatbot.Fixtures do
  @moduledoc """
  This module defines test fixtures for creating test data.
  """

  alias Chatbot.Accounts.User
  alias Chatbot.Chat
  alias Chatbot.Repo

  @doc """
  Generate a unique user email.
  """
  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"

  @doc """
  Generate a user password for tests.
  Meets NIST SP 800-63B-4 minimum length requirement (15+ characters).
  """
  def valid_user_password, do: "Hello_World_123!"

  @doc """
  Generate user attributes for registration.
  """
  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  @doc """
  Generate a user.

  Inserts directly into the database, bypassing the first-user-only
  business logic constraint. This allows tests to create multiple users
  for testing purposes.
  """
  def user_fixture(attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(valid_user_attributes(attrs))
    |> Repo.insert!()
  end

  @doc """
  Generate a conversation.
  """
  def conversation_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()

    {:ok, conversation} =
      attrs
      |> Enum.into(%{
        user_id: user.id,
        title: "Test Conversation"
      })
      |> Chat.create_conversation()

    conversation
  end

  @doc """
  Generate a message.
  """
  def message_fixture(attrs \\ %{}) do
    conversation = attrs[:conversation] || conversation_fixture()

    {:ok, message} =
      attrs
      |> Enum.into(%{
        conversation_id: conversation.id,
        role: "user",
        content: "Test message"
      })
      |> Chat.create_message()

    message
  end

  @doc """
  Generate an attachment.

  Note: When RAG is enabled (default), this will also create chunks for the
  attachment. Use `attachment_fixture_without_chunks/1` to create an attachment
  without triggering chunk processing.
  """
  def attachment_fixture(attrs \\ %{}) do
    conversation = attrs[:conversation] || conversation_fixture()
    default_content = "# Test Attachment\n\nThis is test content."

    {:ok, attachment} =
      attrs
      |> Enum.into(%{
        conversation_id: conversation.id,
        filename: "test_#{System.unique_integer([:positive])}.md",
        content: default_content,
        size_bytes: byte_size(default_content)
      })
      |> Chat.create_attachment()

    attachment
  end

  @doc """
  Generate an attachment without chunk processing.
  Bypasses the RAG chunk processing for tests that don't need it.
  """
  def attachment_fixture_without_chunks(attrs \\ %{}) do
    conversation = attrs[:conversation] || conversation_fixture()
    default_content = "# Test Attachment\n\nThis is test content."

    attrs =
      Enum.into(attrs, %{
        conversation_id: conversation.id,
        filename: "test_#{System.unique_integer([:positive])}.md",
        content: default_content,
        size_bytes: byte_size(default_content)
      })

    %Chat.ConversationAttachment{}
    |> Chat.ConversationAttachment.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Generate an attachment chunk.
  """
  def attachment_chunk_fixture(attrs \\ %{}) do
    attachment = attrs[:attachment] || attachment_fixture_without_chunks()
    conversation_id = attachment.conversation_id
    embedding = attrs[:embedding] || List.duplicate(0.1, 1024)

    default_content = "This is a test chunk content for testing."

    attrs =
      Enum.into(attrs, %{
        attachment_id: attachment.id,
        conversation_id: conversation_id,
        content: default_content,
        chunk_index: 0,
        embedding: embedding,
        metadata: %{headers: ["Test Section"], section_path: "Test Section"}
      })

    %Chat.AttachmentChunk{}
    |> Chat.AttachmentChunk.changeset(attrs)
    |> Repo.insert!()
  end
end
