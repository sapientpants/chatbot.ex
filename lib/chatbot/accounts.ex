defmodule Chatbot.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Chatbot.Repo

  alias Chatbot.Accounts.{User, UserToken}

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## User session

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  ## User queries

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## Session

  @doc """
  Generates a cryptographically secure session token.

  Returns the token value to be sent to the client.

  ## Examples

      iex> generate_user_session_token(user)
      "token_string"
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user by the signed token.

  ## Examples

      iex> get_user_by_session_token(valid_token)
      %User{}

      iex> get_user_by_session_token(invalid_token)
      nil
  """
  def get_user_by_session_token(token) when is_binary(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def get_user_by_session_token(_), do: nil

  @doc """
  Deletes the session token.

  ## Examples

      iex> delete_user_session_token(token)
      :ok
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  @doc """
  Deletes all session tokens for the given user.

  ## Examples

      iex> delete_user_session_tokens(user)
      {count, nil}
  """
  def delete_user_session_tokens(user) do
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["session"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/reset-password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_reset_password_instructions(unknown_user, &url(~p"/reset-password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password")
    Repo.insert!(user_token)
    # For now, just log the reset URL since we don't have email configured
    # In production, you would send an actual email here
    reset_url = reset_password_url_fun.(encoded_token)

    IO.puts("""
    ==============================
    Password Reset Instructions
    ==============================
    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{reset_url}

    If you didn't request this change, please ignore this message.
    ==============================
    """)

    {:ok, %{to: user.email, body: "Password reset instructions sent"}}
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "short", password_confirmation: "short"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Repo.transaction(fn ->
      with {:ok, user} <- update_user_password(user, attrs),
           {_, nil} <-
             {Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"])),
              nil} do
        user
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end
end
