defmodule Chatbot.SecurityLogTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Chatbot.SecurityLog

  describe "auth_failure/3" do
    test "logs authentication failure with masked email" do
      log =
        capture_log(fn ->
          SecurityLog.auth_failure("test@example.com", :invalid_password, %{ip: "1.2.3.4"})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "auth_failure"
      assert log =~ "t***t@example.com"
      assert log =~ "invalid_password"
      refute log =~ "test@example.com"
    end

    test "masks identifier for non-email strings" do
      log =
        capture_log(fn ->
          SecurityLog.auth_failure("longusername123", :invalid_password, %{})
        end)

      assert log =~ "long****"
      refute log =~ "longusername123"
    end

    test "handles nil identifier" do
      log =
        capture_log(fn ->
          SecurityLog.auth_failure(nil, :user_not_found, %{})
        end)

      assert log =~ "auth_failure"
      assert log =~ "user_not_found"
    end
  end

  describe "auth_success/2" do
    test "logs successful authentication" do
      log =
        capture_log(fn ->
          SecurityLog.auth_success("user-123", %{ip: "1.2.3.4"})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "auth_success"
      assert log =~ "user-123"
    end
  end

  describe "rate_limit_exceeded/3" do
    test "logs rate limit events" do
      log =
        capture_log(fn ->
          SecurityLog.rate_limit_exceeded("user-456", :message, %{count: 10})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "rate_limit_exceeded"
      assert log =~ "message"
    end

    test "masks email in rate limit logs" do
      log =
        capture_log(fn ->
          SecurityLog.rate_limit_exceeded("test@domain.com", :login, %{})
        end)

      assert log =~ "t***t@domain.com"
      refute log =~ "test@domain.com"
    end
  end

  describe "ssrf_blocked/3" do
    test "logs SSRF block with masked URL" do
      log =
        capture_log(fn ->
          SecurityLog.ssrf_blocked("http://internal.server/secret/path", :private_ip, %{})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "ssrf_blocked"
      assert log =~ "private_ip"
      assert log =~ "http://internal.server/***"
      refute log =~ "/secret/path"
    end
  end

  describe "mcp_tool_executed/3" do
    test "logs successful tool execution" do
      log =
        capture_log(fn ->
          SecurityLog.mcp_tool_executed("user-789", "calculator", %{duration_ms: 100})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "mcp_tool_executed"
      assert log =~ "calculator"
      assert log =~ "user-789"
    end
  end

  describe "mcp_tool_failed/4" do
    test "logs failed tool execution" do
      log =
        capture_log(fn ->
          SecurityLog.mcp_tool_failed("user-789", "calculator", "Connection timeout", %{})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "mcp_tool_failed"
      assert log =~ "calculator"
      assert log =~ "Connection timeout"
    end

    test "truncates long error messages" do
      long_error = String.duplicate("x", 600)

      log =
        capture_log(fn ->
          SecurityLog.mcp_tool_failed("user-789", "tool", long_error, %{})
        end)

      assert log =~ "..."
      # Should be truncated to 500 chars
      refute log =~ String.duplicate("x", 600)
    end
  end

  describe "authorization_failure/3" do
    test "logs authorization failure" do
      log =
        capture_log(fn ->
          SecurityLog.authorization_failure("user-123", "/admin/settings", %{action: "edit"})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "authorization_failure"
      assert log =~ "/admin/settings"
    end
  end

  describe "suspicious_activity/2" do
    test "logs suspicious activity" do
      log =
        capture_log(fn ->
          SecurityLog.suspicious_activity(:repeated_failures, %{count: 50})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "suspicious_activity"
      assert log =~ "repeated_failures"
    end
  end

  describe "session events" do
    test "logs session creation" do
      log =
        capture_log(fn ->
          SecurityLog.session_created("user-123", %{ip: "1.2.3.4"})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "session_created"
    end

    test "logs session invalidation" do
      log =
        capture_log(fn ->
          SecurityLog.session_invalidated("user-123", :logout, %{})
        end)

      assert log =~ "[SECURITY]"
      assert log =~ "session_invalidated"
      assert log =~ "logout"
    end
  end

  describe "metadata sanitization" do
    test "removes sensitive keys from metadata" do
      log =
        capture_log(fn ->
          SecurityLog.auth_failure("user", :test, %{
            password: "secret123",
            token: "bearer-token",
            api_key: "key123",
            safe_key: "visible"
          })
        end)

      assert log =~ "safe_key"
      assert log =~ "visible"
      refute log =~ "secret123"
      refute log =~ "bearer-token"
      refute log =~ "key123"
    end

    test "truncates long string values in metadata" do
      long_value = String.duplicate("a", 300)

      log =
        capture_log(fn ->
          SecurityLog.auth_failure("user", :test, %{data: long_value})
        end)

      assert log =~ "..."
      # Should be truncated to 200 chars
      refute log =~ String.duplicate("a", 300)
    end
  end
end
