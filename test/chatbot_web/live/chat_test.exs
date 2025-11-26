defmodule ChatbotWeb.ChatLiveTest do
  use ChatbotWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "ChatLive.Index" do
    test "renders chat page with sidebar", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/chat")

      assert html =~ "New Chat"
      assert html =~ "Select model"
    end

    test "displays empty state when no messages", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/chat")

      assert html =~ "How can I help you today?"
    end

    test "shows conversation list in sidebar", %{conn: conn, user: user} do
      # Create a conversation first
      {:ok, _conversation} =
        Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test Conversation"})

      {:ok, _lv, html} = live(conn, ~p"/chat")

      assert html =~ "Test Conversation"
    end

    test "can create new conversation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/chat")

      html =
        lv
        |> element("button", "New Chat")
        |> render_click()

      assert html =~ "New Conversation"
    end

    test "displays user avatar in sidebar", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/chat")

      first_letter = user.email |> String.first() |> String.upcase()
      assert html =~ first_letter
    end
  end

  describe "ChatLive.Show" do
    setup %{user: user} do
      {:ok, conversation} =
        Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test Chat"})

      %{conversation: conversation}
    end

    test "renders conversation page", %{conn: conn, conversation: conversation} do
      {:ok, _lv, html} = live(conn, ~p"/chat/#{conversation.id}")

      assert html =~ "Test Chat"
    end

    test "shows actions menu with export options", %{conn: conn, conversation: conversation} do
      {:ok, _lv, html} = live(conn, ~p"/chat/#{conversation.id}")

      assert html =~ "Export as Markdown"
      assert html =~ "Export as JSON"
      assert html =~ "Delete Conversation"
    end

    test "can show delete confirmation modal", %{conn: conn, conversation: conversation} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{conversation.id}")

      html =
        lv
        |> element("button", "Delete Conversation")
        |> render_click()

      assert html =~ "Delete Conversation?"
      assert html =~ "This action cannot be undone"
    end

    test "can cancel delete modal", %{conn: conn, conversation: conversation} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{conversation.id}")

      lv
      |> element("button", "Delete Conversation")
      |> render_click()

      html =
        lv
        |> element("button", "Cancel")
        |> render_click()

      refute html =~ "Delete Conversation?"
    end

    test "displays message input form", %{conn: conn, conversation: conversation} do
      {:ok, _lv, html} = live(conn, ~p"/chat/#{conversation.id}")

      assert html =~ "Type your message"
      assert html =~ "Press Enter to send"
    end

    test "redirects when conversation not found", %{conn: conn} do
      # Use a valid UUID format that doesn't exist
      fake_id = Ecto.UUID.generate()

      assert {:error, {:redirect, %{to: "/chat", flash: %{"error" => "Conversation not found"}}}} =
               live(conn, ~p"/chat/#{fake_id}")
    end

    test "shows messages when present", %{conn: conn, conversation: conversation} do
      # Create a message
      {:ok, _msg} =
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: "user",
          content: "Hello, this is a test message"
        })

      {:ok, _lv, html} = live(conn, ~p"/chat/#{conversation.id}")

      assert html =~ "Hello, this is a test message"
    end
  end

  describe "ChatLive authorization" do
    test "redirects unauthenticated users to login", %{conn: _conn} do
      unauthenticated_conn = Phoenix.ConnTest.build_conn()
      {:error, {:redirect, %{to: to}}} = live(unauthenticated_conn, ~p"/chat")
      assert to =~ "/login"
    end

    test "cannot access other user's conversation", %{conn: conn} do
      other_user = Chatbot.Fixtures.user_fixture()

      {:ok, other_conversation} =
        Chatbot.Chat.create_conversation(%{user_id: other_user.id, title: "Other's Chat"})

      assert {:error, {:redirect, %{to: "/chat", flash: %{"error" => "Conversation not found"}}}} =
               live(conn, ~p"/chat/#{other_conversation.id}")
    end
  end
end
