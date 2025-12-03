defmodule ChatbotWeb.Live.Chat.MessageComponents do
  @moduledoc """
  Components for displaying chat messages and streaming responses.
  """
  use Phoenix.Component

  import ChatbotWeb.CoreComponents

  @doc """
  Renders a single chat message.
  """
  attr :message, :any, required: true

  @spec chat_message(map()) :: Phoenix.LiveView.Rendered.t()
  def chat_message(assigns) do
    rag_sources = Map.get(assigns.message, :rag_sources, []) || []
    has_sources = rag_sources != [] and assigns.message.role == "assistant"

    assigns =
      assigns
      |> assign(:rag_sources, rag_sources)
      |> assign(:has_sources, has_sources)
      |> assign(:rag_sources_json, if(has_sources, do: Jason.encode!(rag_sources), else: "[]"))
      |> assign(:message_content_id, "message-content-#{assigns.message.id}")

    ~H"""
    <div class={["flex gap-4", @message.role == "user" && "flex-row-reverse"]}>
      <div class={[
        "w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0",
        @message.role == "user" && "bg-primary text-primary-content",
        @message.role != "user" && "bg-gradient-to-br from-violet-500 to-purple-600 text-white"
      ]}>
        <%= if @message.role == "user" do %>
          <.icon name="hero-user" class="w-4 h-4" />
        <% else %>
          <.icon name="hero-sparkles" class="w-4 h-4" />
        <% end %>
      </div>
      <div class={["flex-1 min-w-0", @message.role == "user" && "flex flex-col items-end"]}>
        <div
          id={@message_content_id}
          class={[
            "rounded-2xl px-4 py-3",
            @message.role == "user" &&
              "inline-block max-w-[85%] bg-primary text-primary-content rounded-br-md",
            @message.role != "user" &&
              "inline-block max-w-[85%] bg-base-200 rounded-bl-md border border-base-300 shadow-sm"
          ]}
          phx-hook={if @has_sources, do: "CitationHighlighter"}
          data-rag-sources={@rag_sources_json}
        >
          <.markdown content={@message.content} />
        </div>
        <div class="text-xs text-base-content/40 mt-1.5 px-1">
          {format_timestamp(@message.inserted_at)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the streaming response indicator with partial content.
  """
  attr :streaming_chunks, :list, required: true
  attr :last_valid_html, :any, default: nil

  @spec streaming_response(map()) :: Phoenix.LiveView.Rendered.t()
  # sobelow_skip ["XSS.Raw"]
  def streaming_response(assigns) do
    content = assigns.streaming_chunks |> Enum.reverse() |> IO.iodata_to_binary()

    html =
      if content != "" do
        case Earmark.as_html(content, code_class_prefix: "language-", smartypants: false) do
          {:ok, html_string, _warnings} ->
            html_string |> HtmlSanitizeEx.markdown_html() |> Phoenix.HTML.raw()

          {:error, _html, _errors} ->
            assigns.last_valid_html
        end
      else
        nil
      end

    assigns = assign(assigns, :html, html)

    ~H"""
    <div class="flex gap-4">
      <div class="w-8 h-8 rounded-full bg-gradient-to-br from-violet-500 to-purple-600 text-white flex items-center justify-center flex-shrink-0">
        <.icon name="hero-sparkles" class="w-4 h-4" />
      </div>
      <div class="flex-1 min-w-0">
        <div class="inline-block max-w-[85%] rounded-2xl rounded-bl-md px-4 py-3 bg-base-200 border border-base-300 shadow-sm">
          <%= if @html do %>
            <div class={[
              "prose prose-sm max-w-full dark:prose-invert",
              "prose-p:my-3 prose-p:leading-relaxed",
              "prose-pre:bg-base-300/80 prose-pre:text-base-content prose-pre:rounded-xl prose-pre:p-4 prose-pre:overflow-x-auto prose-pre:my-5 prose-pre:border prose-pre:border-base-content/10 prose-pre:shadow-sm",
              "prose-code:bg-base-300 prose-code:px-1.5 prose-code:py-0.5 prose-code:rounded prose-code:text-sm prose-code:before:content-none prose-code:after:content-none",
              "prose-ul:my-3 prose-ul:list-disc prose-ul:pl-5 prose-ol:my-3 prose-ol:list-decimal prose-ol:pl-5 prose-li:my-1.5 prose-li:marker:text-base-content/60",
              "prose-headings:font-semibold prose-headings:text-base-content prose-h1:text-xl prose-h1:mt-6 prose-h1:mb-3 prose-h2:text-lg prose-h2:mt-5 prose-h2:mb-2 prose-h3:text-base prose-h3:mt-4 prose-h3:mb-2",
              "prose-a:text-primary prose-a:no-underline hover:prose-a:underline",
              "prose-blockquote:border-l-primary prose-blockquote:not-italic prose-blockquote:my-4 prose-blockquote:pl-4",
              "prose-strong:font-semibold prose-strong:text-base-content"
            ]}>
              {@html}
            </div>
          <% end %>
          <span class="loading loading-dots loading-sm text-primary"></span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the messages container with all messages and streaming response.
  """
  attr :messages, :any, required: true, doc: "Stream of messages from LiveView stream/3"
  attr :is_streaming, :boolean, required: true
  attr :streaming_chunks, :list, required: true
  attr :last_valid_html, :any, default: nil

  @spec messages_container(map()) :: Phoenix.LiveView.Rendered.t()
  def messages_container(assigns) do
    ~H"""
    <div
      class="flex-1 overflow-y-auto flex flex-col-reverse"
      id="messages-container"
      role="log"
      aria-label="Chat messages"
      aria-live="polite"
      phx-hook="ScrollToBottom"
    >
      <div class="max-w-3xl w-[100%] mx-auto py-6 px-4 space-y-6">
        <div id="messages-list" phx-update="stream">
          <div :for={{dom_id, message} <- @messages} id={dom_id} class="mb-6">
            <.chat_message message={message} />
          </div>
        </div>

        <%= if @is_streaming do %>
          <div id="streaming-response">
            <.streaming_response
              streaming_chunks={@streaming_chunks}
              last_valid_html={@last_valid_html}
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc "Formats a timestamp for display."
  @spec format_timestamp(DateTime.t() | NaiveDateTime.t() | nil) :: String.t()
  def format_timestamp(nil), do: ""
  def format_timestamp(datetime), do: Calendar.strftime(datetime, "%I:%M %p")
end
