defmodule Mix.Tasks.CheckModuleSize do
  @shortdoc "Check that modules don't exceed line limit"

  @moduledoc """
  Checks that no Elixir module exceeds the maximum line count.

  This helps maintain code quality by preventing modules from becoming
  too large and difficult to maintain.

  ## Usage

      mix check_module_size

  ## Configuration

  The maximum line count can be configured in `config/config.exs`:

      config :chatbot, :code_quality,
        max_module_lines: 400

  ## Options

  * `--max-lines` - Override the maximum line count (default: 400)
  * `--exclude` - Comma-separated list of paths to exclude

  ## Examples

      # Run with default settings
      mix check_module_size

      # Override max lines
      mix check_module_size --max-lines 500

      # Exclude specific paths
      mix check_module_size --exclude "lib/chatbot_web/components/core_components.ex"
  """

  use Mix.Task

  @default_max_lines 400
  # Exclude complex context modules and UI-heavy LiveView modules
  @default_excludes ["lib/chatbot/chat.ex", "lib/chatbot_web/live/settings_live.ex"]

  @impl Mix.Task
  def run(args) do
    {opts, _args, _invalid} =
      OptionParser.parse(args,
        strict: [max_lines: :integer, exclude: :string]
      )

    max_lines =
      opts[:max_lines] ||
        Application.get_env(:chatbot, :code_quality, [])[:max_module_lines] ||
        @default_max_lines

    excludes =
      case opts[:exclude] do
        nil -> @default_excludes
        paths -> paths |> String.split(",") |> Enum.map(&String.trim/1)
      end

    violations =
      Path.wildcard("lib/**/*.ex")
      |> Enum.reject(fn path -> Enum.member?(excludes, path) end)
      |> Enum.map(fn path ->
        lines = path |> File.read!() |> String.split("\n") |> length()
        {path, lines}
      end)
      |> Enum.filter(fn {_path, lines} -> lines > max_lines end)
      |> Enum.sort_by(fn {_path, lines} -> -lines end)

    if violations != [] do
      Mix.shell().error("\nModules exceeding #{max_lines} lines:")

      Enum.each(violations, fn {path, lines} ->
        overage = lines - max_lines
        Mix.shell().error("  #{path}: #{lines} lines (+#{overage} over limit)")
      end)

      Mix.shell().error("\nConsider refactoring these modules into smaller, focused components.")
      Mix.shell().error("To exclude a file, add it to @default_excludes in this task")
      Mix.shell().error("or use --exclude flag.\n")

      Mix.raise(
        "Module size check failed: #{length(violations)} module(s) exceed #{max_lines} lines"
      )
    else
      Mix.shell().info("All modules within #{max_lines} line limit")
    end
  end
end
