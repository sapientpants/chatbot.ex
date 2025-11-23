defmodule ChatbotWeb.UserSessionControllerTest do
  use ChatbotWeb.ConnCase, async: true

  import Chatbot.Fixtures

  # Match the remember me cookie max_age from UserAuth (60 days)
  @remember_me_max_age 60 * 60 * 24 * 60

  setup do
    %{user: user_fixture()}
  end

  describe "POST /login" do
    test "logs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/chat"
      assert get_session(conn, :user_token)
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/login", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      cookie = conn.resp_cookies["_chatbot_web_user_remember_me"]
      assert cookie
      assert cookie.max_age == @remember_me_max_age
      assert cookie.same_site == "Lax"
      assert redirected_to(conn) == ~p"/chat"
    end

    test "shows error with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => "invalid@example.com", "password" => "invalid"}
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
    end

    test "shows error with invalid password", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "invalid"}
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
    end
  end

  describe "DELETE /logout" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Logged out successfully."
    end

    test "logs the user out and deletes remember me cookie", %{conn: conn, user: user} do
      # First login with remember me
      conn =
        post(conn, ~p"/login", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      # Verify cookie was set
      assert conn.resp_cookies["_chatbot_web_user_remember_me"]

      # Then logout
      conn = delete(conn, ~p"/logout")

      # Verify cookie is deleted (max_age: 0 marks it for deletion)
      assert conn.resp_cookies["_chatbot_web_user_remember_me"].max_age == 0
    end
  end
end
