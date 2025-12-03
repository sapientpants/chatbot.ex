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
end
