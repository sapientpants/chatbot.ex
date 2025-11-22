defmodule Chatbot.Repo do
  use Ecto.Repo,
    otp_app: :chatbot,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    {:ok, config}
  end

  def generate_uuid, do: Uniq.UUID.uuid7()
end
