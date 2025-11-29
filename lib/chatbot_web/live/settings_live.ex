defmodule ChatbotWeb.SettingsLive do
  @moduledoc """
  Settings page for configuring LLM providers.

  Allows users to configure:
  - Ollama server URL and embedding model
  - LM Studio enable/disable and URL
  - Which provider to use for completions and embeddings
  """
  use ChatbotWeb, :live_view

  alias Chatbot.LMStudio
  alias Chatbot.ModelCache
  alias Chatbot.Ollama
  alias Chatbot.Settings

  require Logger

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    settings = Settings.all()

    socket =
      socket
      |> assign(:settings, settings)
      |> assign(:ollama_status, :unknown)
      |> assign(:lmstudio_status, :unknown)
      |> assign(:form, to_form(settings, as: :settings))
      |> assign(:saving, false)

    # Test connections on mount
    if connected?(socket) do
      send(self(), :test_connections)
    end

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(:test_connections, socket) do
    # Test Ollama connection
    ollama_status = test_ollama_connection()

    # Test LM Studio connection if enabled
    lmstudio_status =
      if socket.assigns.settings["lmstudio_enabled"] == "true" do
        test_lmstudio_connection()
      else
        :disabled
      end

    {:noreply,
     socket
     |> assign(:ollama_status, ollama_status)
     |> assign(:lmstudio_status, lmstudio_status)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"settings" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :settings))}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"settings" => params}, socket) do
    socket = assign(socket, :saving, true)

    case Settings.set_many(params) do
      :ok ->
        # Clear model cache so new settings take effect
        ModelCache.clear()

        # Reload settings
        settings = Settings.all()

        socket =
          socket
          |> assign(:settings, settings)
          |> assign(:form, to_form(settings, as: :settings))
          |> assign(:saving, false)
          |> put_flash(:info, "Settings saved successfully")

        # Re-test connections
        send(self(), :test_connections)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> put_flash(:error, "Failed to save settings: #{inspect(reason)}")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("test_ollama", _params, socket) do
    status = test_ollama_connection()
    {:noreply, assign(socket, :ollama_status, status)}
  end

  @impl Phoenix.LiveView
  def handle_event("test_lmstudio", _params, socket) do
    status = test_lmstudio_connection()
    {:noreply, assign(socket, :lmstudio_status, status)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <!-- Header -->
      <header class="navbar bg-base-200 border-b border-base-300">
        <div class="flex-1">
          <.link navigate={~p"/chat"} class="btn btn-ghost gap-2">
            <.icon name="hero-arrow-left" class="w-5 h-5" /> Back to Chat
          </.link>
        </div>
        <div class="flex-none">
          <h1 class="text-lg font-semibold">Provider Settings</h1>
        </div>
        <div class="flex-1"></div>
      </header>
      
    <!-- Main Content -->
      <main class="container mx-auto max-w-2xl px-4 py-8">
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-8">
          <!-- Ollama Section -->
          <section class="card bg-base-200">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <h2 class="card-title">
                  <.icon name="hero-server" class="w-5 h-5" /> Ollama
                  <span class="badge badge-primary badge-sm">Required</span>
                </h2>
                <.connection_badge status={@ollama_status} />
              </div>

              <p class="text-base-content/70 text-sm mb-4">
                Ollama is required for embeddings and can handle chat completions.
              </p>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">Server URL</span>
                </label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="settings[ollama_url]"
                    value={@form[:ollama_url].value}
                    class="input input-bordered flex-1"
                    placeholder="http://localhost:11434"
                  />
                  <button type="button" phx-click="test_ollama" class="btn btn-ghost">
                    Test
                  </button>
                </div>
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">Embedding Model</span>
                </label>
                <input
                  type="text"
                  name="settings[ollama_embedding_model]"
                  value={@form[:ollama_embedding_model].value}
                  class="input input-bordered"
                  placeholder="qwen3-embedding:0.6b"
                />
                <label class="label">
                  <span class="label-text-alt text-base-content/50">
                    Used for memory search and fact extraction
                  </span>
                </label>
              </div>
            </div>
          </section>
          
    <!-- LM Studio Section -->
          <section class="card bg-base-200">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <h2 class="card-title">
                  <.icon name="hero-cpu-chip" class="w-5 h-5" /> LM Studio
                  <span class="badge badge-ghost badge-sm">Optional</span>
                </h2>
                <.connection_badge status={@lmstudio_status} />
              </div>

              <p class="text-base-content/70 text-sm mb-4">
                LM Studio can be used as an alternative provider for chat completions.
              </p>

              <div class="form-control">
                <label class="label cursor-pointer justify-start gap-4">
                  <input
                    type="checkbox"
                    name="settings[lmstudio_enabled]"
                    value="true"
                    checked={@form[:lmstudio_enabled].value == "true"}
                    class="toggle toggle-primary"
                  />
                  <span class="label-text">Enable LM Studio</span>
                </label>
              </div>

              <div class={["form-control", @form[:lmstudio_enabled].value != "true" && "opacity-50"]}>
                <label class="label">
                  <span class="label-text">Server URL</span>
                </label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="settings[lmstudio_url]"
                    value={@form[:lmstudio_url].value}
                    class="input input-bordered flex-1"
                    placeholder="http://localhost:1234/v1"
                    disabled={@form[:lmstudio_enabled].value != "true"}
                  />
                  <button
                    type="button"
                    phx-click="test_lmstudio"
                    class="btn btn-ghost"
                    disabled={@form[:lmstudio_enabled].value != "true"}
                  >
                    Test
                  </button>
                </div>
              </div>
            </div>
          </section>
          
    <!-- Provider Selection -->
          <section class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">
                <.icon name="hero-arrows-right-left" class="w-5 h-5" /> Provider Selection
              </h2>

              <p class="text-base-content/70 text-sm mb-4">
                Choose which provider to use for each capability.
              </p>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Chat Completions</span>
                  </label>
                  <select
                    name="settings[completion_provider]"
                    class="select select-bordered"
                  >
                    <option value="ollama" selected={@form[:completion_provider].value == "ollama"}>
                      Ollama
                    </option>
                    <option
                      value="lmstudio"
                      selected={@form[:completion_provider].value == "lmstudio"}
                      disabled={@form[:lmstudio_enabled].value != "true"}
                    >
                      LM Studio
                    </option>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Embeddings</span>
                  </label>
                  <select
                    name="settings[embedding_provider]"
                    class="select select-bordered"
                  >
                    <option value="ollama" selected={@form[:embedding_provider].value == "ollama"}>
                      Ollama
                    </option>
                  </select>
                  <label class="label">
                    <span class="label-text-alt text-base-content/50">
                      Currently only Ollama supports embeddings
                    </span>
                  </label>
                </div>
              </div>
            </div>
          </section>
          
    <!-- Save Button -->
          <div class="flex justify-end gap-2">
            <.link navigate={~p"/chat"} class="btn btn-ghost">
              Cancel
            </.link>
            <button type="submit" class="btn btn-primary" disabled={@saving}>
              <%= if @saving do %>
                <span class="loading loading-spinner loading-sm"></span> Saving...
              <% else %>
                Save Settings
              <% end %>
            </button>
          </div>
        </.form>
      </main>
    </div>
    """
  end

  # Connection status badge component
  attr :status, :atom, required: true

  defp connection_badge(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <%= case @status do %>
        <% :connected -> %>
          <span class="badge badge-success gap-1">
            <.icon name="hero-check-circle" class="w-3 h-3" /> Connected
          </span>
        <% :error -> %>
          <span class="badge badge-error gap-1">
            <.icon name="hero-x-circle" class="w-3 h-3" /> Error
          </span>
        <% :disabled -> %>
          <span class="badge badge-ghost gap-1">
            Disabled
          </span>
        <% :unknown -> %>
          <span class="badge badge-ghost gap-1">
            <span class="loading loading-spinner loading-xs"></span> Testing...
          </span>
      <% end %>
    </div>
    """
  end

  # Test Ollama connection
  defp test_ollama_connection do
    case Ollama.list_models() do
      {:ok, _models} -> :connected
      {:error, _reason} -> :error
    end
  end

  # Test LM Studio connection
  defp test_lmstudio_connection do
    case LMStudio.list_models() do
      {:ok, _models} -> :connected
      {:error, _reason} -> :error
    end
  end
end
