defmodule Chatbot.SettingsTest do
  use Chatbot.DataCase, async: false

  alias Chatbot.Settings

  describe "get/1" do
    test "returns default value for unknown key" do
      assert Settings.get("unknown_key") == nil
    end

    test "returns default value for completion_provider" do
      assert Settings.get("completion_provider") == "ollama"
    end

    test "returns default value for embedding_provider" do
      assert Settings.get("embedding_provider") == "ollama"
    end

    test "returns default value for ollama_url" do
      assert Settings.get("ollama_url") == "http://localhost:11434"
    end

    test "returns default value for lmstudio_enabled" do
      assert Settings.get("lmstudio_enabled") == "false"
    end
  end

  describe "get/2" do
    test "returns provided default for unknown key" do
      assert Settings.get("unknown_key", "my_default") == "my_default"
    end
  end

  describe "get_boolean/1" do
    test "returns false for lmstudio_enabled by default" do
      refute Settings.get_boolean("lmstudio_enabled")
    end

    test "returns false for unknown key" do
      refute Settings.get_boolean("unknown_key")
    end
  end

  describe "set/2" do
    test "sets a value and retrieves it" do
      assert :ok = Settings.set("test_key", "test_value")
      assert Settings.get("test_key") == "test_value"
    end

    test "updates an existing value" do
      :ok = Settings.set("update_key", "value1")
      assert Settings.get("update_key") == "value1"

      :ok = Settings.set("update_key", "value2")
      assert Settings.get("update_key") == "value2"
    end
  end

  describe "set_many/1" do
    test "sets multiple values at once" do
      settings = %{
        "multi_key1" => "value1",
        "multi_key2" => "value2"
      }

      assert :ok = Settings.set_many(settings)
      assert Settings.get("multi_key1") == "value1"
      assert Settings.get("multi_key2") == "value2"
    end
  end

  describe "all/0" do
    test "returns all settings including defaults" do
      settings = Settings.all()

      assert settings["completion_provider"] == "ollama"
      assert settings["embedding_provider"] == "ollama"
      assert settings["ollama_url"] == "http://localhost:11434"
      assert settings["lmstudio_enabled"] == "false"
    end

    test "includes custom settings" do
      :ok = Settings.set("custom_setting", "custom_value")
      settings = Settings.all()

      assert settings["custom_setting"] == "custom_value"
    end
  end

  describe "defaults/0" do
    test "returns the default settings map" do
      defaults = Settings.defaults()

      assert Map.has_key?(defaults, "completion_provider")
      assert Map.has_key?(defaults, "embedding_provider")
      assert Map.has_key?(defaults, "ollama_url")
      assert Map.has_key?(defaults, "lmstudio_enabled")
    end
  end

  describe "reload/0" do
    test "reloads settings from database" do
      # Set a value
      :ok = Settings.set("reload_test", "before_reload")
      assert Settings.get("reload_test") == "before_reload"

      # Reload should preserve the value
      :ok = Settings.reload()
      assert Settings.get("reload_test") == "before_reload"
    end
  end
end
