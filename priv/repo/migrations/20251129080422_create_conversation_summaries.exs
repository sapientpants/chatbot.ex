defmodule Chatbot.Repo.Migrations.CreateConversationSummaries do
  use Ecto.Migration

  def change do
    create table(:conversation_summaries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :content, :text, null: false
      add :message_range_start, :integer, null: false
      add :message_range_end, :integer, null: false
      add :token_count, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:conversation_summaries, [:conversation_id])
    create unique_index(:conversation_summaries, [:conversation_id, :message_range_start])
  end
end
