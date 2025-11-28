defmodule Chatbot.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias Chatbot.Accounts.User
  alias Chatbot.Accounts.UserNotifier
  alias Chatbot.Accounts.UserToken
  alias Chatbot.Repo

  require Logger

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
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
  @spec change_user_registration(User.t(), map()) :: Ecto.Changeset.t()
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
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)

    # Use constant-time comparison to prevent timing attacks
    # that could reveal whether an email exists in the database
    if User.valid_password?(user, password) do
      user
    else
      # Perform a dummy hash comparison to maintain constant time
      # even when the user doesn't exist
      Bcrypt.no_user_verify()
      nil
    end
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
  @spec get_user!(binary()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  ## Session

  @doc """
  Generates a cryptographically secure session token.

  Returns the token value to be sent to the client.

  ## Examples

      iex> generate_user_session_token(user)
      "token_string"
  """
  @spec generate_user_session_token(User.t()) :: String.t()
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
  @spec get_user_by_session_token(String.t() | nil) :: User.t() | nil
  def get_user_by_session_token(token) when is_binary(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @spec get_user_by_session_token(nil) :: nil
  def get_user_by_session_token(_invalid_token), do: nil

  @doc """
  Deletes the session token.

  ## Examples

      iex> delete_user_session_token(token)
      :ok
  """
  @spec delete_user_session_token(String.t()) :: :ok
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
  @spec delete_user_session_tokens(User.t()) :: {non_neg_integer(), nil}
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
  @spec deliver_user_reset_password_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, map()}
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password")
    Repo.insert!(user_token)
    # For now, just log the reset URL since we don't have email configured
    # In production, you would send an actual email here
    reset_url = reset_password_url_fun.(encoded_token)

    Logger.debug("""
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
  @spec get_user_by_reset_password_token(String.t()) :: User.t() | nil
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token),
         %User{} = user <- Repo.one(query) do
      user
    else
      _error -> nil
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
  @spec reset_user_password(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def reset_user_password(user, attrs) do
    Repo.transaction(fn ->
      with {:ok, user} <- update_user_password(user, attrs),
           {_count, nil} <-
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
  @spec change_user_password(User.t(), map()) :: Ecto.Changeset.t()
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
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  ## Email confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  @spec deliver_user_confirmation_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, map()} | {:error, :already_confirmed}
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.

  ## Examples

      iex> confirm_user("valid_token")
      {:ok, %User{}}

      iex> confirm_user("invalid_token")
      :error

  """
  @spec confirm_user(String.t()) :: {:ok, User.t()} | :error
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _error -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end
end
