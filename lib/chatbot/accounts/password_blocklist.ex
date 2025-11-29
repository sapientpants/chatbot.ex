defmodule Chatbot.Accounts.PasswordBlocklist do
  @moduledoc """
  Password blocklist for preventing use of commonly compromised passwords.

  Per NIST SP 800-63B-4 guidelines, verifiers SHALL check passwords against
  a blocklist of known compromised or commonly used passwords.

  This module provides a basic blocklist of the most common passwords.
  For production use, consider integrating with HaveIBeenPwned's API or
  using a more comprehensive blocklist.
  """

  # Top 100 most common passwords (based on various leaked password databases)
  # This is a minimal set - production should use a larger list or API
  @common_passwords MapSet.new([
                      # Common words and patterns
                      "password",
                      "password1",
                      "password12",
                      "password123",
                      "password1234",
                      "password12345",
                      "password123456",
                      "123456789012345",
                      "1234567890123456",
                      "qwertyuiopasdfgh",
                      "qwertyuiopasdfghjkl",
                      "qwerty123456789",
                      "letmein123456",
                      "welcome123456",
                      "admin123456789",
                      "administrator123",
                      "iloveyou123456",
                      "sunshine123456",
                      "princess123456",
                      "football123456",
                      "baseball123456",
                      "abc123456789012",
                      "abcdefghijklmno",
                      "monkey12345678",
                      "shadow12345678",
                      "master12345678",
                      "dragon12345678",
                      "michael1234567",
                      "jennifer123456",
                      "trustno1234567",
                      "changeme123456",
                      "passw0rd123456",
                      "p@ssword123456",
                      "p@ssw0rd123456",
                      "secret12345678",
                      "starwars123456",
                      "whatever123456",
                      "freedom1234567",
                      "nothing1234567",
                      "computer123456",
                      "internet123456",
                      "killer12345678",
                      "batman12345678",
                      "superman123456",
                      "asdfghjklzxcvbn",
                      "zxcvbnmasdfghjk",
                      "1qaz2wsx3edc4rfv",
                      "qazwsxedcrfvtgby",
                      "1234qwer5678asdf",
                      "aaaaaaaaaaaaaaa",
                      "111111111111111",
                      "000000000000000",
                      # Keyboard patterns (15+ chars)
                      "qwertyuiop12345",
                      "asdfghjkl123456",
                      "zxcvbnm12345678",
                      "1234567890qwerty",
                      "0987654321asdfg",
                      # Common phrases
                      "iloveyouforever",
                      "letmeinnow12345",
                      "pleaseletmein12",
                      "opensesame12345",
                      "abracadabra1234",
                      "helloworld12345",
                      "goodmorning1234",
                      "goodnightmoon12",
                      "happybirthday12",
                      "merrychristmas1"
                    ])

  @doc """
  Checks if a password is in the blocklist.

  Returns `true` if the password is blocked (commonly used/compromised),
  `false` if the password is acceptable.

  ## Examples

      iex> Chatbot.Accounts.PasswordBlocklist.blocked?("password123456")
      true

      iex> Chatbot.Accounts.PasswordBlocklist.blocked?("MyUniqueSecurePhrase!")
      false

  """
  @spec blocked?(String.t()) :: boolean()
  def blocked?(password) when is_binary(password) do
    normalized = String.downcase(password)
    MapSet.member?(@common_passwords, normalized)
  end

  def blocked?(_other), do: false

  @doc """
  Returns an error message suitable for user display when password is blocked.
  """
  @spec blocked_message() :: String.t()
  def blocked_message do
    "is a commonly used password and cannot be used"
  end
end
