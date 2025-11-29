defmodule Chatbot.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  require Logger

  @app :chatbot

  @spec migrate() :: :ok | no_return()
  def migrate do
    load_app()

    for repo <- repos() do
      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
        {:ok, _fun_return, _apps} ->
          :ok

        {:error, error} ->
          Logger.error("Migration failed for #{inspect(repo)}: #{inspect(error)}")
          System.halt(1)
      end
    end

    :ok
  end

  @spec rollback(module(), integer()) :: {:ok, any(), [atom()]} | {:error, any()}
  def rollback(repo, version) do
    load_app()

    case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version)) do
      {:ok, fun_return, apps} -> {:ok, fun_return, apps}
      {:error, reason} -> {:error, reason}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
