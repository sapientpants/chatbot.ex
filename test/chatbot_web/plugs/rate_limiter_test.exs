defmodule ChatbotWeb.Plugs.RateLimiterTest do
  use ChatbotWeb.ConnCase, async: false

  alias ChatbotWeb.Plugs.RateLimiter

  # We need async: false because Hammer uses ETS and rate limits are shared

  setup do
    # Clear Hammer state between tests
    {:ok, _} = Hammer.delete_buckets("login:*")
    {:ok, _} = Hammer.delete_buckets("registration:*")
    {:ok, _} = Hammer.delete_buckets("messages:*")
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
      Enum.each(1..5, fn _ ->
        RateLimiter.rate_limit_login(conn, [])
      end)

      # 6th request should be denied
      result = RateLimiter.rate_limit_login(conn, [])
      assert result.halted
      assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Too many login attempts"
      assert redirected_to(result) == "/login"
    end

    test "uses IP address for rate limiting", %{conn: conn} do
      conn1 = %{conn | remote_ip: {10, 0, 0, 1}}
      conn2 = %{conn | remote_ip: {10, 0, 0, 2}}

      # Max out rate limit for first IP
      Enum.each(1..5, fn _ ->
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
      Enum.each(1..3, fn _ ->
        RateLimiter.rate_limit_registration(conn, [])
      end)

      # 4th request should be denied
      result = RateLimiter.rate_limit_registration(conn, [])
      assert result.halted
      assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Too many registration attempts"
      assert redirected_to(result) == "/register"
    end

    test "uses IP address for rate limiting", %{conn: conn} do
      conn1 = %{conn | remote_ip: {172, 16, 0, 1}}
      conn2 = %{conn | remote_ip: {172, 16, 0, 2}}

      # Max out rate limit for first IP
      Enum.each(1..3, fn _ ->
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
      Enum.each(1..30, fn _ ->
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
      Enum.each(1..30, fn _ ->
        RateLimiter.check_message_rate_limit(user_id1)
      end)

      # Second user should still be allowed
      assert RateLimiter.check_message_rate_limit(user_id2) == :ok
    end
  end
end
