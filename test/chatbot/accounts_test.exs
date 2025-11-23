defmodule Chatbot.AccountsTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Accounts
  alias Chatbot.Accounts.User
  import Chatbot.Fixtures

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid", password: "short"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("a", 200)
      {:error, changeset} = Accounts.register_user(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()

      {:error, changeset} =
        Accounts.register_user(%{email: email, password: valid_user_password()})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.password)
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_registration(%User{})
      assert changeset.required == [:password, :email]
    end

    test "allows fields to be set" do
      email = unique_user_email()
      password = valid_user_password()

      changeset =
        Accounts.change_user_registration(
          %User{},
          valid_user_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{email: email} = user = user_fixture()

      assert %User{} =
               returned_user =
               Accounts.get_user_by_email_and_password(email, valid_user_password())

      assert returned_user.id == user.id
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!("00000000-0000-0000-0000-000000000000")
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "generate_user_session_token/1" do
    test "returns user id as token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert token == user.id
    end
  end

  describe "get_user_by_session_token/1" do
    test "returns user by token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert %User{id: id} = Accounts.get_user_by_session_token(token)
      assert id == user.id
    end

    test "returns nil for invalid token" do
      assert Accounts.get_user_by_session_token("00000000-0000-0000-0000-000000000000") == nil
    end

    test "returns nil for non-binary token" do
      assert Accounts.get_user_by_session_token(123) == nil
    end
  end

  describe "delete_user_session_token/1" do
    test "returns :ok" do
      assert Accounts.delete_user_session_token("any_token") == :ok
    end
  end
end
