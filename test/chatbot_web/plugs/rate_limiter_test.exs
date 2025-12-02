defmodule ChatbotWeb.Plugs.RateLimiterTest do
  use ChatbotWeb.ConnCase, async: false

  alias ChatbotWeb.Plugs.RateLimiter

  # We need async: false because Hammer uses ETS and rate limits are shared

  setup do
    # Clear Hammer state between tests
    {:ok, _deleted} = Hammer.delete_buckets("login:*")
    {:ok, _deleted} = Hammer.delete_buckets("registration:*")
    {:ok, _deleted} = Hammer.delete_buckets("messages:*")
    :ok
  end

  describe "init/1" do
    test "returns the options unchanged" do
      opts = %{some: "option"}
      assert RateLimiter.init(opts) == opts
    end
  end

  describe "call/2" do
    test "routes to the appropriate rate limiter function", %{conn: conn} do
      conn =
        conn
        |> Map.put(:remote_ip, {200, 200, 200, 1})
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      result = RateLimiter.call(conn, :rate_limit_login)
      assert result.remote_ip == {200, 200, 200, 1}
      refute result.halted
    end
  end

  describe "rate_limit_login/2" do
    test "allows request when under rate limit", %{conn: conn} do
      conn =
        conn
        |> Map.put(:remote_ip, {201, 201, 201, 1})
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      result = RateLimiter.rate_limit_login(conn, [])
      refute result.halted
    end

    test "denies request when over rate limit", %{conn: conn} do
      conn =
        conn
        |> Map.put(:remote_ip, {192, 168, 1, 1})
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      # Make 5 requests (the limit)
      Enum.each(1..5, fn _i ->
        RateLimiter.rate_limit_login(conn, [])
      end)

      # 6th request should be denied
      result = RateLimiter.rate_limit_login(conn, [])
      assert result.halted
      assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Too many login attempts"
      assert redirected_to(result) == "/login"
    end

    test "uses IP address for rate limiting", %{conn: conn} do
      conn1 =
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 1})
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      conn2 =
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 2})
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      # Max out rate limit for first IP
      Enum.each(1..5, fn _i ->
        RateLimiter.rate_limit_login(conn1, [])
      end)

      # Second IP should still be allowed
      result = RateLimiter.rate_limit_login(conn2, [])
      refute result.halted
    end
  end

  describe "rate_limit_registration/2" do
    test "allows request when under rate limit", %{conn: conn} do
      conn =
        conn
        |> Map.put(:remote_ip, {127, 0, 0, 2})
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      result = RateLimiter.rate_limit_registration(conn, [])
      refute result.halted
    end

    test "denies request when over rate limit", %{conn: conn} do
      conn =
        conn
        |> Map.put(:remote_ip, {192, 168, 1, 2})
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      # Make 3 requests (the limit)
      Enum.each(1..3, fn _i ->
        RateLimiter.rate_limit_registration(conn, [])
      end)

      # 4th request should be denied
      result = RateLimiter.rate_limit_registration(conn, [])
      assert result.halted
      assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Too many registration attempts"
      assert redirected_to(result) == "/register"
    end

    test "uses IP address for rate limiting", %{conn: conn} do
      conn1 =
        conn
        |> Map.put(:remote_ip, {172, 16, 0, 1})
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      conn2 =
        conn
        |> Map.put(:remote_ip, {172, 16, 0, 2})
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      # Max out rate limit for first IP
      Enum.each(1..3, fn _i ->
        RateLimiter.rate_limit_registration(conn1, [])
      end)

      # Second IP should still be allowed
      result = RateLimiter.rate_limit_registration(conn2, [])
      refute result.halted
    end
  end

  describe "check_message_rate_limit/1" do
    test "allows message when under rate limit" do
      user_id = "user-123"
      assert RateLimiter.check_message_rate_limit(user_id) == :ok
    end

    test "denies message when over rate limit" do
      user_id = "user-456"

      # Make 30 requests (the limit)
      Enum.each(1..30, fn _i ->
        RateLimiter.check_message_rate_limit(user_id)
      end)

      # 31st request should be denied
      assert {:error, message} = RateLimiter.check_message_rate_limit(user_id)
      assert message =~ "Rate limit exceeded"
    end

    test "uses user_id for rate limiting" do
      user_id1 = "user-789"
      user_id2 = "user-101"

      # Max out rate limit for first user
      Enum.each(1..30, fn _i ->
        RateLimiter.check_message_rate_limit(user_id1)
      end)

      # Second user should still be allowed
      assert RateLimiter.check_message_rate_limit(user_id2) == :ok
    end
  end

  describe "check_registration_rate_limit/1" do
    test "allows registration when under rate limit" do
      ip = "192.168.1.100"
      assert RateLimiter.check_registration_rate_limit(ip) == :ok
    end

    test "denies registration when over rate limit" do
      ip = "192.168.1.101"

      # Make 3 requests (the limit)
      Enum.each(1..3, fn _i ->
        RateLimiter.check_registration_rate_limit(ip)
      end)

      # 4th request should be denied
      assert {:error, message} = RateLimiter.check_registration_rate_limit(ip)
      assert message =~ "Too many registration attempts"
    end

    test "uses IP for rate limiting" do
      ip1 = "192.168.1.102"
      ip2 = "192.168.1.103"

      # Max out rate limit for first IP
      Enum.each(1..3, fn _i ->
        RateLimiter.check_registration_rate_limit(ip1)
      end)

      # Second IP should still be allowed
      assert RateLimiter.check_registration_rate_limit(ip2) == :ok
    end
  end

  describe "get_ip/1 security" do
    test "uses remote_ip when no X-Forwarded-For header" do
      conn = %Plug.Conn{
        remote_ip: {8, 8, 8, 8},
        req_headers: []
      }

      assert RateLimiter.get_ip(conn) == "8.8.8.8"
    end

    test "ignores X-Forwarded-For by default (no trusted proxies configured)" do
      # By default, no proxies are trusted - prevents IP spoofing
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "203.0.113.50"}]
      }

      # Should use remote_ip, not the header
      assert RateLimiter.get_ip(conn) == "127.0.0.1"
    end

    test "trusts X-Forwarded-For when proxy is explicitly configured" do
      # Configure loopback as trusted proxy
      Application.put_env(:chatbot, :rate_limits, trusted_proxies: [{{127, 0, 0, 0}, 8}])

      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "203.0.113.50"}]
      }

      assert RateLimiter.get_ip(conn) == "203.0.113.50"

      # Cleanup
      Application.delete_env(:chatbot, :rate_limits)
    end

    test "trusts X-Forwarded-For from configured private network proxy" do
      # Configure 10.x.x.x as trusted proxy
      Application.put_env(:chatbot, :rate_limits, trusted_proxies: [{{10, 0, 0, 0}, 8}])

      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "198.51.100.25"}]
      }

      assert RateLimiter.get_ip(conn) == "198.51.100.25"

      # Cleanup
      Application.delete_env(:chatbot, :rate_limits)
    end

    test "ignores X-Forwarded-For from untrusted public IP" do
      # Public IP trying to spoof X-Forwarded-For should be ignored
      conn = %Plug.Conn{
        remote_ip: {203, 0, 113, 1},
        req_headers: [{"x-forwarded-for", "1.2.3.4"}]
      }

      # Should return the actual remote_ip, not the spoofed header
      assert RateLimiter.get_ip(conn) == "203.0.113.1"
    end

    test "handles multiple IPs in X-Forwarded-For from configured trusted proxy" do
      # Configure 192.168.x.x as trusted proxy
      Application.put_env(:chatbot, :rate_limits, trusted_proxies: [{{192, 168, 0, 0}, 16}])

      conn = %Plug.Conn{
        remote_ip: {192, 168, 1, 1},
        req_headers: [{"x-forwarded-for", "203.0.113.50, 10.0.0.1, 192.168.1.1"}]
      }

      # Should use the first valid IP (the original client)
      assert RateLimiter.get_ip(conn) == "203.0.113.50"

      # Cleanup
      Application.delete_env(:chatbot, :rate_limits)
    end

    test "rejects invalid IP in X-Forwarded-For header" do
      # Configure loopback as trusted proxy
      Application.put_env(:chatbot, :rate_limits, trusted_proxies: [{{127, 0, 0, 0}, 8}])

      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "invalid-ip, not-an-ip"}]
      }

      # Should fall back to remote_ip since no valid IP in header
      assert RateLimiter.get_ip(conn) == "127.0.0.1"

      # Cleanup
      Application.delete_env(:chatbot, :rate_limits)
    end

    test "finds first valid IP when header contains mix of valid and invalid" do
      # Configure loopback as trusted proxy
      Application.put_env(:chatbot, :rate_limits, trusted_proxies: [{{127, 0, 0, 0}, 8}])

      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "invalid, 203.0.113.50, 10.0.0.1"}]
      }

      # Should skip invalid and use first valid IP
      assert RateLimiter.get_ip(conn) == "203.0.113.50"

      # Cleanup
      Application.delete_env(:chatbot, :rate_limits)
    end

    test "handles IPv6 remote_ip" do
      conn = %Plug.Conn{
        remote_ip: {0, 0, 0, 0, 0, 0, 0, 1},
        req_headers: []
      }

      assert RateLimiter.get_ip(conn) == "0:0:0:0:0:0:0:1"
    end

    test "ignores X-Forwarded-For from private IP when not configured as trusted" do
      # Even private IPs should not be trusted by default
      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "1.2.3.4"}]
      }

      # Should use remote_ip, not the header
      assert RateLimiter.get_ip(conn) == "10.0.0.1"
    end
  end
end
