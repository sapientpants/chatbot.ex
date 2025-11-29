defmodule Chatbot.PIITest do
  use ExUnit.Case, async: true

  alias Chatbot.PII

  describe "mask_email/1" do
    test "masks a standard email" do
      assert PII.mask_email("john.doe@example.com") == "j***@e***.com"
    end

    test "masks email with short local part" do
      assert PII.mask_email("a@example.com") == "a***@e***.com"
    end

    test "masks email with short domain" do
      assert PII.mask_email("user@b.co") == "u***@b***.co"
    end

    test "handles nil" do
      assert PII.mask_email(nil) == "[no email]"
    end

    test "handles empty string" do
      assert PII.mask_email("") == "[no email]"
    end

    test "handles invalid email without @" do
      assert PII.mask_email("notanemail") == "[invalid email]"
    end

    test "masks email with subdomain" do
      assert PII.mask_email("user@mail.example.com") == "u***@m***.example.com"
    end

    test "masks email with multiple dots in domain" do
      assert PII.mask_email("user@sub.domain.co.uk") == "u***@s***.domain.co.uk"
    end
  end
end
