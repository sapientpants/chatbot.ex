defmodule Chatbot.Accounts.PasswordBlocklistTest do
  use ExUnit.Case, async: true

  alias Chatbot.Accounts.PasswordBlocklist

  describe "blocked?/1" do
    test "returns true for common passwords" do
      assert PasswordBlocklist.blocked?("password123456")
      assert PasswordBlocklist.blocked?("qwertyuiopasdfgh")
      assert PasswordBlocklist.blocked?("123456789012345")
      assert PasswordBlocklist.blocked?("letmein123456")
    end

    test "is case insensitive" do
      assert PasswordBlocklist.blocked?("PASSWORD123456")
      assert PasswordBlocklist.blocked?("Password123456")
      assert PasswordBlocklist.blocked?("QWERTYUIOPASDFGH")
    end

    test "returns false for unique passwords" do
      refute PasswordBlocklist.blocked?("MySecurePassphrase2024!")
      refute PasswordBlocklist.blocked?("correct horse battery staple")
      refute PasswordBlocklist.blocked?("xK9#mP2$vL8@nQ5")
    end

    test "returns false for nil" do
      refute PasswordBlocklist.blocked?(nil)
    end
  end

  describe "blocked_message/0" do
    test "returns user-friendly error message" do
      message = PasswordBlocklist.blocked_message()
      assert is_binary(message)
      assert String.contains?(message, "commonly used")
    end
  end
end
