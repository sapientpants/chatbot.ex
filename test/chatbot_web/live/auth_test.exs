defmodule ChatbotWeb.AuthLiveTest do
  use ChatbotWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "LoginLive" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "Log in"
      assert html =~ "Email"
      assert html =~ "Password"
    end

    test "has link to register page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")
      assert html =~ "Sign up"
      assert html =~ ~s(href="/register")
    end
  end

  describe "RegisterLive" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/register")

      assert html =~ "Create an account"
      assert html =~ "Email"
      assert html =~ "Password"
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/register")

      html =
        lv
        |> form("#registration_form", user: %{email: "invalid", password: "short"})
        |> render_change()

      assert html =~ "must have the @ sign and no spaces"
    end
  end

  describe "ForgotPasswordLive" do
    test "renders forgot password page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/forgot-password")

      assert html =~ "Forgot your password?"
      assert html =~ "Email"
      assert html =~ "Send reset link"
    end
  end
end
