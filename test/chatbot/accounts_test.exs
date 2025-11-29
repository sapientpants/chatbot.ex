defmodule Chatbot.AccountsTest do
  use Chatbot.DataCase, async: true

  import Ecto.Query
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

      errors = errors_on(changeset)
      assert errors.email == ["must have the @ sign and no spaces"]
      # NIST SP 800-63B-4 compliant: only length requirement, no composition rules
      assert "should be at least 15 character(s)" in errors.password
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("a", 200)
      {:error, changeset} = Accounts.register_user(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 128 character(s)" in errors_on(changeset).password
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
    test "generates a cryptographically secure token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert is_binary(token)
      assert byte_size(token) > 20
      # Token should not be the user ID
      refute token == user.id
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

  describe "get_user_by_email/1" do
    test "returns user by email" do
      user = user_fixture()
      assert %User{} = Accounts.get_user_by_email(user.email)
    end

    test "returns nil for unknown email" do
      assert Accounts.get_user_by_email("unknown@example.com") == nil
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    test "sends reset instructions and returns ok tuple" do
      user = user_fixture()

      {:ok, result} =
        Accounts.deliver_user_reset_password_instructions(user, fn _token -> "url" end)

      assert result.to == user.email
    end
  end

  describe "get_user_by_reset_password_token/1" do
    test "returns user by valid token" do
      user = user_fixture()

      # The token returned by this function is the encoded token that would be sent to the user
      {:ok, _notification} =
        Accounts.deliver_user_reset_password_instructions(user, fn token ->
          # Capture the token for testing
          send(self(), {:reset_token, token})
          "url"
        end)

      # Receive the token from the message
      assert_receive {:reset_token, token}

      assert %User{} = Accounts.get_user_by_reset_password_token(token)
    end

    test "returns nil for invalid token" do
      assert Accounts.get_user_by_reset_password_token("invalid") == nil
    end
  end

  describe "reset_user_password/2" do
    test "resets the password" do
      user = user_fixture()
      new_password = "NewValidPassword123!"

      {:ok, updated_user} =
        Accounts.reset_user_password(user, %{
          password: new_password,
          password_confirmation: new_password
        })

      assert updated_user.id == user.id
      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "deletes all reset password tokens after successful reset" do
      user = user_fixture()

      {:ok, _notification} =
        Accounts.deliver_user_reset_password_instructions(user, fn token -> token end)

      new_password = "NewValidPassword123!"

      {:ok, _updated_user} =
        Accounts.reset_user_password(user, %{
          password: new_password,
          password_confirmation: new_password
        })

      # Verify all reset password tokens are deleted
      token_query =
        from t in Chatbot.Accounts.UserToken,
          where: t.user_id == ^user.id and t.context == "reset_password"

      refute Chatbot.Repo.exists?(token_query)
    end

    test "returns error changeset for invalid password" do
      user = user_fixture()

      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "short",
          password_confirmation: "short"
        })

      assert %Ecto.Changeset{} = changeset
      assert "should be at least 15 character(s)" in errors_on(changeset).password
    end
  end

  describe "change_user_password/2" do
    test "returns a changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Accounts.change_user_password(user)
    end

    test "validates password" do
      user = user_fixture()

      changeset =
        Accounts.change_user_password(user, %{
          password: "short",
          password_confirmation: "short"
        })

      refute changeset.valid?
      assert "should be at least 15 character(s)" in errors_on(changeset).password
    end
  end
end
