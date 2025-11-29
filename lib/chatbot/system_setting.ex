defmodule Chatbot.SystemSetting do
  @moduledoc """
  Schema for system-wide configuration settings stored in the database.

  Settings are key-value pairs where values are stored as text (JSON-encoded
  for complex types).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime]

  schema "system_settings" do
    field :value, :string

    timestamps()
  end

  @doc false
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
  end
end
