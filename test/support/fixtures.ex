defmodule Chatbot.Fixtures do
  @moduledoc """
  This module defines test fixtures for creating test data.
  """

  alias Chatbot.Accounts
  alias Chatbot.Chat

  @doc """
  Generate a unique user email.
  """
  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"

  @doc """
  Generate a user password for tests.
  Meets complexity requirements: uppercase, lowercase, number, and special character.
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

  By default creates a confirmed user for easier testing.
  Pass `confirmed: false` to create an unconfirmed user.
  """
  def user_fixture(attrs \\ %{}) do
    {confirmed, attrs} = Map.pop(attrs, :confirmed, true)

    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    if confirmed do
      # Confirm the user directly in the database for testing
      user
      |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now(:second)})
      |> Chatbot.Repo.update!()
    else
      user
    end
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
end
