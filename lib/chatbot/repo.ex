defmodule Chatbot.Repo do
  @moduledoc """
  Main repository for database access using Ecto.

  Uses PostgreSQL as the database adapter and generates UUIDv7 for primary keys.
  """
  use Ecto.Repo,
    otp_app: :chatbot,
    adapter: Ecto.Adapters.Postgres

  @impl Ecto.Repo
  def init(_type, config) do
    {:ok, config}
  end

  @spec generate_uuid() :: String.t()
  def generate_uuid, do: Uniq.UUID.uuid7()
end
