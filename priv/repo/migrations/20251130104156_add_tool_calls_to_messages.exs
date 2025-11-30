defmodule Chatbot.Repo.Migrations.AddToolCallsToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      # For assistant messages that request tool calls: [{id, name, arguments}]
      add :tool_calls, :jsonb

      # For tool result messages - references the tool_call this responds to
      add :tool_call_id, :string
      add :tool_name, :string
      add :tool_result, :jsonb
      add :tool_error, :text
      add :tool_duration_ms, :integer
    end

    create index(:messages, [:conversation_id, :tool_call_id])
  end
end
