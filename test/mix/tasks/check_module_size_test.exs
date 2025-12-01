defmodule Mix.Tasks.CheckModuleSizeTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.CheckModuleSize

  describe "run/1" do
    test "passes when all modules are under the limit" do
      # The task should pass with default excludes
      output =
        capture_io(fn ->
          CheckModuleSize.run([])
        end)

      assert output =~ "All modules within"
    end

    test "supports --max-lines flag" do
      output =
        capture_io(fn ->
          CheckModuleSize.run(["--max-lines", "1000"])
        end)

      assert output =~ "All modules within 1000 line limit"
    end

    test "fails when modules exceed limit without excludes" do
      # Use a very low limit to trigger failure
      assert_raise Mix.Error, ~r/Module size check failed/, fn ->
        capture_io(:stderr, fn ->
          CheckModuleSize.run(["--max-lines", "10"])
        end)
      end
    end
  end
end
