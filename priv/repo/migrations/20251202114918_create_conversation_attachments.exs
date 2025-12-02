defmodule Chatbot.Repo.Migrations.CreateConversationAttachments do
  use Ecto.Migration

  def change do
    create table(:conversation_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :filename, :string, null: false
      add :content, :text, null: false
      add :content_type, :string, null: false, default: "text/markdown"
      add :size_bytes, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:conversation_attachments, [:conversation_id])
  end
end
