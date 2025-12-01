defmodule Chatbot.URLValidatorTest do
  use ExUnit.Case, async: true

  alias Chatbot.URLValidator

  describe "validate_url/1" do
    test "accepts valid http URLs" do
      assert {:ok, "http://localhost:11434"} = URLValidator.validate_url("http://localhost:11434")
      assert {:ok, "http://localhost"} = URLValidator.validate_url("http://localhost")
      assert {:ok, "http://example.com"} = URLValidator.validate_url("http://example.com")

      assert {:ok, "http://192.168.1.1:8080"} =
               URLValidator.validate_url("http://192.168.1.1:8080")
    end

    test "accepts valid https URLs" do
      assert {:ok, "https://api.example.com"} =
               URLValidator.validate_url("https://api.example.com")

      assert {:ok, "https://localhost:1234"} = URLValidator.validate_url("https://localhost:1234")
    end

    test "normalizes trailing slashes" do
      assert {:ok, "http://localhost:11434"} =
               URLValidator.validate_url("http://localhost:11434/")
    end

    test "rejects file:// scheme" do
      assert {:error, "URL must use http or https scheme"} =
               URLValidator.validate_url("file:///etc/passwd")
    end

    test "rejects javascript: scheme" do
      assert {:error, "URL must use http or https scheme"} =
               URLValidator.validate_url("javascript:alert(1)")
    end

    test "rejects ftp:// scheme" do
      assert {:error, "URL must use http or https scheme"} =
               URLValidator.validate_url("ftp://ftp.example.com")
    end

    test "rejects URLs without proper scheme" do
      # localhost:11434 parses as scheme=localhost, so it gets rejected as invalid scheme
      assert {:error, "URL must use http or https scheme"} =
               URLValidator.validate_url("localhost:11434")
    end

    test "rejects URLs without host" do
      assert {:error, _reason} = URLValidator.validate_url("http://")
    end

    test "rejects invalid URL format" do
      assert {:error, "Invalid URL format"} = URLValidator.validate_url("not a url at all")
    end

    test "rejects URLs with credentials" do
      assert {:error, "URL must not contain credentials"} =
               URLValidator.validate_url("http://user:pass@localhost:11434")
    end

    test "rejects invalid port numbers" do
      assert {:error, "Invalid port number"} = URLValidator.validate_url("http://localhost:99999")
    end

    test "rejects cloud metadata service IP" do
      assert {:error, "Access to cloud metadata services is not allowed"} =
               URLValidator.validate_url("http://169.254.169.254/latest/meta-data")
    end

    test "rejects cloud metadata hostname" do
      assert {:error, "Access to cloud metadata services is not allowed"} =
               URLValidator.validate_url("http://metadata.google.internal/")
    end

    test "rejects non-string input" do
      assert {:error, "URL must be a string"} = URLValidator.validate_url(nil)
      assert {:error, "URL must be a string"} = URLValidator.validate_url(123)
    end

    test "trims whitespace" do
      assert {:ok, "http://localhost:11434"} =
               URLValidator.validate_url("  http://localhost:11434  ")
    end
  end

  describe "valid_url?/1" do
    test "returns true for valid URLs" do
      assert URLValidator.valid_url?("http://localhost:11434")
      assert URLValidator.valid_url?("https://example.com")
    end

    test "returns false for invalid URLs" do
      refute URLValidator.valid_url?("file:///etc/passwd")
      refute URLValidator.valid_url?("not a url")
      refute URLValidator.valid_url?(nil)
    end
  end

  describe "validate_url!/1" do
    test "returns normalized URL for valid input" do
      assert "http://localhost:11434" = URLValidator.validate_url!("http://localhost:11434")
    end

    test "raises ArgumentError for invalid input" do
      assert_raise ArgumentError, ~r/Invalid URL/, fn ->
        URLValidator.validate_url!("file:///etc/passwd")
      end
    end
  end
end
