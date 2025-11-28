defmodule Chatbot.Accounts.UserToken do
  @moduledoc """
  Schema for user authentication tokens.

  Stores secure, hashed tokens for user sessions with expiration support.
  """

  use Ecto.Schema
  import Ecto.Query

  @type t :: %__MODULE__{
          id: binary() | nil,
          token: binary() | nil,
          context: String.t() | nil,
          user_id: binary() | nil,
          inserted_at: DateTime.t() | nil
        }

  @hash_algorithm :sha256
  @rand_size 32

  # Session tokens expire after 7 days (reduced from 60 for security)
  @session_validity_in_days 7
  # Reset password tokens expire after 1 day
  @reset_password_validity_in_days 1
  # Email confirmation tokens expire after 7 days
  @confirm_validity_in_days 7

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    belongs_to :user, Chatbot.Accounts.User
    field :inserted_at, :utc_datetime
  end

  @doc """
  Generates a token for the given context and user.

  Returns the token value (to be sent to client) and the token struct (to be stored in DB).
  """
  @spec build_session_token(Chatbot.Accounts.User.t()) :: {String.t(), t()}
  def build_session_token(user) do
    build_hashed_token(user, "session")
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.
  """
  @spec verify_session_token_query(String.t()) :: {:ok, Ecto.Query.t()}
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email for password reset.

  The non-hashed token is sent to the user email while the hashed part is stored in the database.
  The original token cannot be reconstructed from the hashed version.
  """
  @spec build_hashed_token(Chatbot.Accounts.User.t(), String.t()) :: {String.t(), t()}
  def build_hashed_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %Chatbot.Accounts.UserToken{
       id: Chatbot.Repo.generate_uuid(),
       token: hashed_token,
       context: context,
       user_id: user.id,
       inserted_at: DateTime.utc_now(:second)
     }}
  end

  @doc """
  Checks if the reset password token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.
  """
  @spec verify_reset_password_token_query(String.t()) :: {:ok, Ecto.Query.t()}
  def verify_reset_password_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "reset_password"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@reset_password_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Returns the token struct for the given token value and context.
  """
  @spec by_token_and_context_query(String.t(), String.t()) :: Ecto.Query.t()
  def by_token_and_context_query(token, context) do
    from Chatbot.Accounts.UserToken, where: [token: ^hash_token(token), context: ^context]
  end

  defp hash_token(token) do
    # Decode the Base64-encoded token before hashing
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} -> :crypto.hash(@hash_algorithm, decoded)
      # Return a hash that will never match any valid token
      :error -> <<0::256>>
    end
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  @spec by_user_and_contexts_query(Chatbot.Accounts.User.t(), [String.t()]) :: Ecto.Query.t()
  def by_user_and_contexts_query(user, contexts) do
    from t in Chatbot.Accounts.UserToken,
      where: t.user_id == ^user.id and t.context in ^contexts
  end

  @doc """
  Checks if the confirmation token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.
  """
  @spec verify_email_token_query(String.t(), String.t()) :: {:ok, Ecto.Query.t()}
  def verify_email_token_query(token, context) do
    query =
      from token in by_token_and_context_query(token, context),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@confirm_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Builds an email token for the given user and context.

  Returns the token value (to be sent to client) and the token struct (to be stored in DB).
  """
  @spec build_email_token(Chatbot.Accounts.User.t(), String.t()) :: {String.t(), t()}
  def build_email_token(user, context) do
    build_hashed_token(user, context)
  end
end
