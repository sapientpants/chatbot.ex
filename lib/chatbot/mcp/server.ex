defmodule Chatbot.MCP.Server do
  @moduledoc """
  Schema for MCP server configurations.

  MCP servers can be configured with either STDIO transport (for local CLI tools)
  or HTTP transport (for remote servers).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type transport_type :: :stdio | :http

  @type t :: %__MODULE__{
          id: binary() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          transport_type: String.t() | nil,
          command: String.t() | nil,
          args: [String.t()] | nil,
          env: map() | nil,
          base_url: String.t() | nil,
          headers: map() | nil,
          enabled: boolean() | nil,
          global: boolean() | nil,
          user_id: binary() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mcp_servers" do
    field :name, :string
    field :description, :string
    field :transport_type, :string
    field :command, :string
    field :args, {:array, :string}, default: []
    field :env, :map, default: %{}
    field :base_url, :string
    field :headers, :map, default: %{}
    field :enabled, :boolean, default: true
    field :global, :boolean, default: false

    belongs_to :user, Chatbot.Accounts.User

    has_many :user_tool_configs, Chatbot.MCP.UserToolConfig, foreign_key: :mcp_server_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for an MCP server.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(server, attrs) do
    server
    |> cast(attrs, [
      :name,
      :description,
      :transport_type,
      :command,
      :args,
      :env,
      :base_url,
      :headers,
      :enabled,
      :global,
      :user_id
    ])
    |> validate_required([:name, :transport_type])
    |> validate_inclusion(:transport_type, ["stdio", "http"])
    |> validate_transport_config()
    |> unique_constraint([:name, :user_id], name: :mcp_servers_name_user_unique)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_transport_config(changeset) do
    case get_field(changeset, :transport_type) do
      "stdio" ->
        changeset
        |> validate_required([:command])
        |> validate_length(:command, min: 1)

      "http" ->
        changeset
        |> validate_required([:base_url])
        |> validate_format(:base_url, ~r/^https?:\/\//)

      _other_type ->
        changeset
    end
  end
end
