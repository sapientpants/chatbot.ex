defmodule Chatbot.MCP.UserToolConfig do
  @moduledoc """
  Schema for per-user tool configurations.

  Each user can enable or disable specific tools from MCP servers.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          tool_name: String.t() | nil,
          enabled: boolean() | nil,
          user_id: binary() | nil,
          mcp_server_id: binary() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_tool_configs" do
    field :tool_name, :string
    field :enabled, :boolean, default: true

    belongs_to :user, Chatbot.Accounts.User
    belongs_to :mcp_server, Chatbot.MCP.Server

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a user tool configuration.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:tool_name, :enabled, :user_id, :mcp_server_id])
    |> validate_required([:tool_name, :user_id, :mcp_server_id])
    |> unique_constraint([:user_id, :mcp_server_id, :tool_name], name: :user_tool_configs_unique)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:mcp_server_id)
  end
end
