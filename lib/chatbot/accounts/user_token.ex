defmodule Chatbot.Accounts.UserToken do
  @moduledoc """
  Schema for user authentication tokens.

  Stores secure, hashed tokens for user sessions with expiration support.
  """
  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32

  # Session tokens expire after 60 days
  @session_validity_in_days 60

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
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %Chatbot.Accounts.UserToken{
       id: Chatbot.Repo.generate_uuid(),
       token: hashed_token,
       context: "session",
       user_id: user.id,
       inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Returns the token struct for the given token value and context.
  """
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
  def by_user_and_contexts_query(user, contexts) do
    from t in Chatbot.Accounts.UserToken,
      where: t.user_id == ^user.id and t.context in ^contexts
  end
end
