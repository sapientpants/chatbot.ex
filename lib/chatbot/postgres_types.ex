Postgrex.Types.define(
  Chatbot.PostgresTypes,
  Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(),
  []
)
