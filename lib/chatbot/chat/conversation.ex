defmodule Chatbot.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :title, :string
    field :model_name, :string
    field :user_id, :binary_id

    belongs_to :user, Chatbot.Accounts.User, define_field: false
    has_many :messages, Chatbot.Chat.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :model_name, :user_id])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
    |> maybe_put_uuid()
  end

  defp maybe_put_uuid(changeset) do
    if get_field(changeset, :id) do
      changeset
    else
      put_change(changeset, :id, Chatbot.Repo.generate_uuid())
    end
  end
end
