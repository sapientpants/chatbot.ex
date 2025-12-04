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
      |> assign(:available_models, [])
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

    # Load available models for the dropdown
    available_models = load_available_models()

    {:noreply,
     socket
     |> assign(:ollama_status, ollama_status)
     |> assign(:lmstudio_status, lmstudio_status)
     |> assign(:available_models, available_models)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"settings" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :settings))}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"settings" => params}, socket) do
    socket = assign(socket, :saving, true)

    # Validate URLs before saving
    with :ok <- validate_url_settings(params),
         :ok <- Settings.set_many(params) do
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
    else
      {:error, :invalid_url, field, reason} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:form, to_form(params, as: :settings))
         |> put_flash(:error, "Invalid #{humanize_field(field)}: #{reason}")}

      {:error, reason} ->
        error_msg =
          case reason do
            %Ecto.Changeset{} -> "Invalid settings data. Please check your inputs."
            _other -> "Failed to save settings. Please try again."
          end

        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:form, to_form(params, as: :settings))
         |> put_flash(:error, error_msg)}
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

  # Validate URL settings
  defp validate_url_settings(params) do
    alias Chatbot.URLValidator

    url_fields = ["ollama_url", "lmstudio_url"]

    Enum.reduce_while(url_fields, :ok, fn field, :ok ->
      case Map.get(params, field) do
        nil ->
          {:cont, :ok}

        "" ->
          {:cont, :ok}

        url ->
          case URLValidator.validate_url(url) do
            {:ok, _url} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, :invalid_url, field, reason}}
          end
      end
    end)
  end

  defp humanize_field("ollama_url"), do: "Ollama URL"
  defp humanize_field("lmstudio_url"), do: "LM Studio URL"
  defp humanize_field(field), do: field

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <.page_header />
      <main class="container mx-auto max-w-2xl px-4 py-8">
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-8">
          <.ollama_section form={@form} status={@ollama_status} />
          <.lmstudio_section form={@form} status={@lmstudio_status} />
          <.provider_section form={@form} available_models={@available_models} />
          <.save_buttons saving={@saving} />
        </.form>
      </main>
    </div>
    """
  end

  defp page_header(assigns) do
    ~H"""
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
    """
  end

  attr :form, :any, required: true
  attr :status, :atom, required: true

  defp ollama_section(assigns) do
    ~H"""
    <section class="card bg-base-200">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title">
            <.icon name="hero-server" class="w-5 h-5" /> Ollama
            <span class="badge badge-primary badge-sm">Required</span>
          </h2>
          <.connection_badge status={@status} />
        </div>
        <p class="text-base-content/70 text-sm mb-4">
          Ollama is required for embeddings and can handle chat completions.
        </p>
        <div class="form-control">
          <label class="label"><span class="label-text">Server URL</span></label>
          <div class="flex gap-2">
            <input
              type="text"
              name="settings[ollama_url]"
              value={@form[:ollama_url].value}
              class="input input-bordered flex-1"
              placeholder="http://localhost:11434"
            />
            <button type="button" phx-click="test_ollama" class="btn btn-ghost">Test</button>
          </div>
        </div>
        <div class="form-control">
          <label class="label"><span class="label-text">Embedding Model</span></label>
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
    """
  end

  attr :form, :any, required: true
  attr :status, :atom, required: true

  defp lmstudio_section(assigns) do
    ~H"""
    <section class="card bg-base-200">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title">
            <.icon name="hero-cpu-chip" class="w-5 h-5" /> LM Studio
            <span class="badge badge-ghost badge-sm">Optional</span>
          </h2>
          <.connection_badge status={@status} />
        </div>
        <p class="text-base-content/70 text-sm mb-4">
          LM Studio can be used as an alternative provider for chat completions.
        </p>
        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-4">
            <input type="hidden" name="settings[lmstudio_enabled]" value="false" />
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
          <label class="label"><span class="label-text">Server URL</span></label>
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
    """
  end

  attr :form, :any, required: true
  attr :available_models, :list, required: true

  defp provider_section(assigns) do
    ~H"""
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
            <label class="label"><span class="label-text">Chat Completions</span></label>
            <select name="settings[completion_provider]" class="select select-bordered">
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
            <label class="label"><span class="label-text">Embeddings</span></label>
            <select name="settings[embedding_provider]" class="select select-bordered">
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
        <div class="form-control mt-4">
          <label class="label"><span class="label-text">Default Model for RAG</span></label>
          <select name="settings[default_model]" class="select select-bordered">
            <option
              value=""
              selected={is_nil(@form[:default_model].value) or @form[:default_model].value == ""}
            >
              Auto (use first available)
            </option>
            <%= for model <- @available_models do %>
              <option value={model} selected={@form[:default_model].value == model}>{model}</option>
            <% end %>
          </select>
          <label class="label">
            <span class="label-text-alt text-base-content/50">
              Used for reranking and query expansion in RAG
            </span>
          </label>
        </div>
      </div>
    </section>
    """
  end

  attr :saving, :boolean, required: true

  defp save_buttons(assigns) do
    ~H"""
    <div class="flex justify-end gap-2">
      <.link navigate={~p"/chat"} class="btn btn-ghost">Cancel</.link>
      <button type="submit" class="btn btn-primary" disabled={@saving}>
        <%= if @saving do %>
          <span class="loading loading-spinner loading-sm"></span> Saving...
        <% else %>
          Save Settings
        <% end %>
      </button>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp connection_badge(%{status: :connected} = assigns),
    do: ~H|<span class="badge badge-success gap-1">
  <.icon name="hero-check-circle" class="w-3 h-3" /> Connected
</span>|

  defp connection_badge(%{status: :error} = assigns),
    do:
      ~H|<span class="badge badge-error gap-1"><.icon name="hero-x-circle" class="w-3 h-3" /> Error</span>|

  defp connection_badge(%{status: :disabled} = assigns),
    do: ~H|<span class="badge badge-ghost gap-1">Disabled</span>|

  defp connection_badge(%{status: :unknown} = assigns),
    do: ~H|<span class="badge badge-ghost gap-1">
  <span class="loading loading-spinner loading-xs"></span> Testing...
</span>|

  defp test_ollama_connection,
    do: if(match?({:ok, _}, Ollama.list_models()), do: :connected, else: :error)

  defp test_lmstudio_connection,
    do: if(match?({:ok, _}, LMStudio.list_models()), do: :connected, else: :error)

  defp load_available_models do
    case ModelCache.get_models() do
      {:ok, models} -> Enum.map(models, & &1["id"])
      {:error, _reason} -> []
    end
  end
end
