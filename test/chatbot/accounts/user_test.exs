defmodule Chatbot.Accounts.UserTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Accounts.User
  import Chatbot.Fixtures

  describe "registration_changeset/3" do
    test "validates email format" do
      changeset =
        User.registration_changeset(%User{}, %{email: "invalid", password: valid_user_password()})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates email length" do
      too_long = String.duplicate("a", 150) <> "@example.com"

      changeset =
        User.registration_changeset(%User{}, %{email: too_long, password: valid_user_password()})

      assert %{email: ["should be at most 160 character(s)"]} = errors_on(changeset)
    end

    test "validates password length" do
      changeset =
        User.registration_changeset(%User{}, %{email: unique_user_email(), password: "short"})

      errors = errors_on(changeset)
      assert "should be at least 12 character(s)" in errors.password

      too_long = String.duplicate("a", 80)

      changeset =
        User.registration_changeset(%User{}, %{email: unique_user_email(), password: too_long})

      errors = errors_on(changeset)
      assert "should be at most 72 character(s)" in errors.password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()

      {:error, changeset} =
        Repo.insert(
          User.registration_changeset(%User{}, %{
            email: email,
            password: valid_user_password()
          })
        )

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "hashes password by default" do
      password = valid_user_password()

      changeset =
        User.registration_changeset(%User{}, %{
          email: unique_user_email(),
          password: password
        })

      assert changeset.valid?
      assert get_change(changeset, :hashed_password)
      refute get_change(changeset, :password)
    end

    test "does not hash password when hash_password: false" do
      password = valid_user_password()

      changeset =
        User.registration_changeset(%User{}, %{email: unique_user_email(), password: password},
          hash_password: false
        )

      assert changeset.valid?
      refute get_change(changeset, :hashed_password)
      assert get_change(changeset, :password) == password
    end

    test "does not validate email uniqueness when validate_email: false" do
      %{email: email} = user_fixture()

      changeset =
        User.registration_changeset(%User{}, %{email: email, password: valid_user_password()},
          validate_email: false
        )

      assert changeset.valid?
    end

    test "generates UUID for new user" do
      changeset =
        User.registration_changeset(%User{}, %{
          email: unique_user_email(),
          password: valid_user_password()
        })

      assert get_change(changeset, :id)
    end

    test "does not generate UUID if already set" do
      existing_id = Chatbot.Repo.generate_uuid()
      user = %User{id: existing_id}

      changeset =
        User.registration_changeset(user, %{
          email: unique_user_email(),
          password: valid_user_password()
        })

      assert get_field(changeset, :id) == existing_id
      refute get_change(changeset, :id)
    end
  end

  describe "email_changeset/3" do
    test "validates email" do
      changeset = User.email_changeset(%User{}, %{email: "invalid"})
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      user = %User{email: "old@example.com"}
      {:error, changeset} = Repo.insert(User.email_changeset(user, %{email: email}))
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "requires email to change" do
      user = %User{email: "test@example.com"}
      changeset = User.email_changeset(user, %{email: "test@example.com"})
      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "does not validate email uniqueness when validate_email: false" do
      %{email: email} = user_fixture()
      user = %User{email: "old@example.com"}
      changeset = User.email_changeset(user, %{email: email}, validate_email: false)
      assert changeset.valid?
    end
  end

  describe "password_changeset/3" do
    test "validates password" do
      changeset = User.password_changeset(%User{}, %{password: "short"})
      errors = errors_on(changeset)
      assert "should be at least 12 character(s)" in errors.password
    end

    test "validates password confirmation" do
      changeset =
        User.password_changeset(%User{}, %{
          password: valid_user_password(),
          password_confirmation: "different"
        })

      assert %{password_confirmation: ["does not match password"]} = errors_on(changeset)
    end

    test "hashes password by default" do
      password = valid_user_password()
      changeset = User.password_changeset(%User{}, %{password: password})

      assert changeset.valid?
      assert get_change(changeset, :hashed_password)
      refute get_change(changeset, :password)
    end

    test "does not hash password when hash_password: false" do
      password = valid_user_password()
      changeset = User.password_changeset(%User{}, %{password: password}, hash_password: false)

      assert changeset.valid?
      refute get_change(changeset, :hashed_password)
      assert get_change(changeset, :password)
    end
  end

  describe "valid_password?/2" do
    test "validates password" do
      user = user_fixture()
      assert User.valid_password?(user, valid_user_password())
      refute User.valid_password?(user, "invalid")
    end

    test "returns false when user is nil" do
      refute User.valid_password?(nil, valid_user_password())
    end

    test "returns false when hashed_password is nil" do
      user = %User{hashed_password: nil}
      refute User.valid_password?(user, valid_user_password())
    end
  end

  describe "validate_current_password/2" do
    test "validates current password" do
      user = user_fixture()

      changeset =
        User.validate_current_password(Ecto.Changeset.change(user), valid_user_password())

      assert changeset.valid?
    end

    test "adds error for invalid password" do
      user = user_fixture()
      changeset = User.validate_current_password(Ecto.Changeset.change(user), "invalid")
      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end
  end
end
