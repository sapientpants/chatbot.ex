defmodule ChatbotWeb.Live.Chat.InputComponents do
  @moduledoc """
  Components for chat input forms and empty states.
  """
  use Phoenix.Component

  import ChatbotWeb.CoreComponents

  alias Chatbot.Chat.ConversationAttachment

  @doc """
  Renders the message input form with file attachment support.
  """
  attr :form, :any, required: true
  attr :is_streaming, :boolean, required: true
  attr :id, :string, default: "message-input"
  attr :uploads, :any, default: nil
  attr :attachments, :list, default: []

  @spec message_input_form(map()) :: Phoenix.LiveView.Rendered.t()
  def message_input_form(assigns) do
    ~H"""
    <div class="border-t border-base-300 bg-base-100 p-4">
      <div class="max-w-3xl mx-auto">
        <.attachment_list attachments={@attachments} uploads={@uploads} />
        <.form
          for={@form}
          phx-submit="send_message"
          phx-change="validate_upload"
          aria-label="Send message"
        >
          <div class="relative flex items-end gap-2 bg-base-200 rounded-2xl p-2 focus-within:ring-2 focus-within:ring-primary focus-within:ring-offset-2 focus-within:ring-offset-base-100 transition-shadow">
            <.attachment_button uploads={@uploads} is_streaming={@is_streaming} />
            <textarea
              name="message[content]"
              placeholder="Type your message..."
              rows="1"
              class="flex-1 bg-transparent border-none text-base resize-none min-h-[40px] max-h-[200px] py-2 px-3 focus:outline-none placeholder:text-base-content/40"
              disabled={@is_streaming}
              aria-label="Message input"
              phx-hook="AutoGrowTextarea"
              id={@id}
            ></textarea>
            <button
              type="submit"
              disabled={@is_streaming}
              class={[
                "btn btn-circle btn-sm flex-shrink-0 transition-all",
                @is_streaming && "btn-ghost",
                !@is_streaming && "btn-primary"
              ]}
              aria-label="Send message"
            >
              <%= if @is_streaming do %>
                <span class="loading loading-spinner loading-sm"></span>
              <% else %>
                <.icon name="hero-arrow-up" class="w-4 h-4" />
              <% end %>
            </button>
          </div>
          <p class="text-xs text-center text-base-content/40 mt-2">
            Press Enter to send, Shift+Enter for new line
          </p>
        </.form>
      </div>
    </div>
    """
  end

  attr :uploads, :any, required: true
  attr :is_streaming, :boolean, required: true

  defp attachment_button(assigns) do
    max_files = ConversationAttachment.max_attachments_per_conversation()
    max_size_kb = div(ConversationAttachment.max_file_size(), 1024)

    assigns =
      assigns
      |> assign(:max_files, max_files)
      |> assign(:max_size_kb, max_size_kb)

    ~H"""
    <div class="relative">
      <label
        class={[
          "btn btn-circle btn-sm btn-ghost cursor-pointer",
          @is_streaming && "btn-disabled"
        ]}
        title={"Attach markdown files (max #{@max_files} files, #{@max_size_kb}KB each)"}
      >
        <.icon name="hero-paper-clip" class="w-4 h-4" />
        <%= if @uploads do %>
          <.live_file_input upload={@uploads.markdown_files} class="hidden" />
        <% end %>
      </label>
    </div>
    """
  end

  attr :attachments, :list, required: true
  attr :uploads, :any, required: true

  defp attachment_list(assigns) do
    has_attachments = length(assigns.attachments) > 0
    has_pending = assigns.uploads && length(assigns.uploads.markdown_files.entries) > 0

    assigns =
      assigns
      |> assign(:has_attachments, has_attachments)
      |> assign(:has_pending, has_pending)

    ~H"""
    <%= if @has_attachments or @has_pending do %>
      <div class="mb-3 flex flex-wrap gap-2">
        <%= for attachment <- @attachments do %>
          <.attachment_chip
            id={attachment.id}
            filename={attachment.filename}
            size={attachment.size_bytes}
            type={:saved}
          />
        <% end %>

        <%= if @uploads do %>
          <%= for entry <- @uploads.markdown_files.entries do %>
            <.attachment_chip
              id={entry.ref}
              filename={entry.client_name}
              size={entry.client_size}
              type={:pending}
              progress={entry.progress}
              errors={upload_errors(@uploads.markdown_files, entry)}
            />
          <% end %>

          <%= if length(@uploads.markdown_files.entries) > 0 do %>
            <button type="button" phx-click="upload_files" class="btn btn-xs btn-primary">
              Upload Files
            </button>
          <% end %>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :filename, :string, required: true
  attr :size, :integer, required: true
  attr :type, :atom, required: true
  attr :progress, :integer, default: 0
  attr :errors, :list, default: []

  defp attachment_chip(assigns) do
    size_display = format_file_size(assigns.size)
    assigns = assign(assigns, :size_display, size_display)

    ~H"""
    <div class={[
      "flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm",
      @type == :saved && "bg-base-300",
      @type == :pending && "bg-primary/10 border border-primary/20"
    ]}>
      <.icon name="hero-document-text" class="w-4 h-4 text-primary" />
      <span class="truncate max-w-[150px]" title={@filename}>{@filename}</span>
      <span class="text-xs text-base-content/50">({@size_display})</span>

      <%= if @type == :pending and @progress > 0 and @progress < 100 do %>
        <span class="text-xs text-primary">{@progress}%</span>
      <% end %>

      <%= for error <- @errors do %>
        <span class="text-xs text-error">{error_to_string(error)}</span>
      <% end %>

      <button
        type="button"
        phx-click={if @type == :saved, do: "remove_attachment", else: "cancel_upload"}
        phx-value-id={if @type == :saved, do: @id, else: nil}
        phx-value-ref={if @type == :pending, do: @id, else: nil}
        class="btn btn-circle btn-ghost btn-xs"
        aria-label="Remove attachment"
      >
        <.icon name="hero-x-mark" class="w-3 h-3" />
      </button>
    </div>
    """
  end

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes), do: "#{div(bytes, 1024)} KB"

  defp error_to_string(:too_large), do: "File too large"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(:not_accepted), do: "Invalid file type"
  defp error_to_string(_error), do: "Upload error"

  @doc """
  Renders the empty chat state with welcome message.
  """
  attr :form, :any, required: true
  attr :is_streaming, :boolean, required: true
  attr :uploads, :any, default: nil
  attr :attachments, :list, default: []

  @spec empty_chat_state(map()) :: Phoenix.LiveView.Rendered.t()
  def empty_chat_state(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col items-center justify-center p-6">
      <div class="text-center mb-8 max-w-md">
        <div class="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-6">
          <.icon name="hero-chat-bubble-bottom-center-text" class="w-8 h-8 text-primary" />
        </div>
        <h2 class="text-2xl font-semibold mb-3">How can I help you today?</h2>
        <p class="text-base-content/60">
          I can help with coding, writing, analysis, brainstorming, and much more.
          Attach markdown files to provide context for your questions.
        </p>
      </div>
      <div class="w-full max-w-2xl">
        <.attachment_list attachments={@attachments} uploads={@uploads} />
        <.form
          for={@form}
          phx-submit="send_message"
          phx-change="validate_upload"
          aria-label="Send message"
        >
          <div class="relative">
            <div class="absolute left-3 bottom-3 z-10">
              <.attachment_button uploads={@uploads} is_streaming={@is_streaming} />
            </div>
            <textarea
              name="message[content]"
              placeholder="Type your message..."
              rows="3"
              class="textarea textarea-bordered w-full text-base resize-none pl-14 pr-14 focus:textarea-primary focus:outline-none"
              disabled={@is_streaming}
              aria-label="Message input"
              id="empty-state-input"
              phx-hook="AutoGrowTextarea"
            ></textarea>
            <button
              type="submit"
              disabled={@is_streaming}
              class="absolute right-3 bottom-3 btn btn-primary btn-sm btn-circle"
              aria-label="Send message"
            >
              <.icon name="hero-arrow-up" class="w-4 h-4" />
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
