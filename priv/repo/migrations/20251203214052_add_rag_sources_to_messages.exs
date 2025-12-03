defmodule Chatbot.Repo.Migrations.AddRagSourcesToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      # Stores RAG citation sources for assistant messages
      # Format: [%{index: 1, filename: "doc.md", section: "Intro", content: "..."}]
      add :rag_sources, {:array, :map}, default: []
    end
  end
end
