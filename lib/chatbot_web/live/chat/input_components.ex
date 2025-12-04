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
  attr :pending_saves, :list, default: []
  attr :attachments_expanded, :boolean, default: true

  @spec message_input_form(map()) :: Phoenix.LiveView.Rendered.t()
  def message_input_form(assigns) do
    assigns = assign(assigns, :is_processing_files, processing_files?(assigns))

    ~H"""
    <div class="border-t border-base-300 bg-base-100 p-4">
      <div class="max-w-3xl mx-auto">
        <.attachment_panel
          attachments={@attachments}
          uploads={@uploads}
          pending_saves={@pending_saves}
          expanded={@attachments_expanded}
        />
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
              aria-label="Message input"
              phx-hook="AutoGrowTextarea"
              id={@id}
              data-processing-files={@is_processing_files}
            ></textarea>
            <%= if @is_streaming do %>
              <button
                type="button"
                phx-click="stop_streaming"
                class="btn btn-circle btn-sm flex-shrink-0 btn-error"
                aria-label="Stop generating"
              >
                <.icon name="hero-stop" class="w-4 h-4" />
              </button>
            <% else %>
              <button
                type="submit"
                class={[
                  "btn btn-circle btn-sm flex-shrink-0",
                  @is_processing_files && "btn-disabled",
                  not @is_processing_files && "btn-primary"
                ]}
                disabled={@is_processing_files}
                aria-label="Send message"
              >
                <.icon name="hero-arrow-up" class="w-4 h-4" />
              </button>
            <% end %>
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
    max_size_bytes = ConversationAttachment.max_file_size()
    max_size_display = format_file_size(max_size_bytes)

    assigns =
      assigns
      |> assign(:max_files, max_files)
      |> assign(:max_size_display, max_size_display)

    ~H"""
    <div class="relative">
      <label
        class={[
          "btn btn-circle btn-sm btn-ghost cursor-pointer",
          @is_streaming && "btn-disabled"
        ]}
        title={"Attach markdown files (max #{@max_files} files, #{@max_size_display} each)"}
        aria-label="Attach markdown files"
      >
        <.icon name="hero-paper-clip" class="w-4 h-4" />
        <%= if @uploads do %>
          <.live_file_input upload={@uploads.markdown_files} class="hidden" />
        <% end %>
      </label>
    </div>
    """
  end

  @collapse_threshold 3

  attr :attachments, :list, required: true
  attr :uploads, :any, required: true
  attr :pending_saves, :list, default: []
  attr :expanded, :boolean, default: true

  defp attachment_panel(assigns) do
    upload_count = active_upload_count(assigns.uploads)
    total_count = length(assigns.attachments) + length(assigns.pending_saves) + upload_count
    has_pending = upload_count > 0 || assigns.pending_saves != []
    should_collapse = total_count > @collapse_threshold and not has_pending

    assigns =
      assigns
      |> assign(:total_count, total_count)
      |> assign(:should_collapse, should_collapse)
      |> assign(:total_size, Enum.sum(Enum.map(assigns.attachments, & &1.size_bytes)))

    ~H"""
    <%= if @total_count > 0 do %>
      <div class="mb-3">
        <%= if @should_collapse and not @expanded do %>
          <.attachment_summary
            count={@total_count}
            total_size={@total_size}
          />
        <% else %>
          <.attachment_grid
            attachments={@attachments}
            uploads={@uploads}
            pending_saves={@pending_saves}
            collapsible={@should_collapse}
            compact={@should_collapse}
          />
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :count, :integer, required: true
  attr :total_size, :integer, required: true

  defp attachment_summary(assigns) do
    size_display = format_file_size(assigns.total_size)
    assigns = assign(assigns, :size_display, size_display)

    ~H"""
    <div class="flex items-center gap-2 p-2 bg-base-200 rounded-lg">
      <.icon name="hero-paper-clip" class="w-4 h-4 text-primary" />
      <span class="text-sm flex-1">{@count} files attached ({@size_display})</span>
      <button
        type="button"
        phx-click="toggle_attachments"
        class="btn btn-xs btn-ghost gap-1"
      >
        Show all <.icon name="hero-chevron-down" class="w-3 h-3" />
      </button>
    </div>
    """
  end

  attr :attachments, :list, required: true
  attr :uploads, :any, required: true
  attr :pending_saves, :list, default: []
  attr :collapsible, :boolean, default: false
  attr :compact, :boolean, default: false

  defp attachment_grid(assigns) do
    ~H"""
    <div>
      <%= if @collapsible do %>
        <div class="flex justify-end mb-1">
          <button type="button" phx-click="toggle_attachments" class="btn btn-xs btn-ghost gap-1">
            Collapse <.icon name="hero-chevron-up" class="w-3 h-3" />
          </button>
        </div>
      <% end %>
      <div class="flex flex-wrap gap-1.5">
        <%= for attachment <- @attachments do %>
          <.attachment_chip
            id={attachment.id}
            filename={attachment.filename}
            size={attachment.size_bytes}
            type={:saved}
            compact={@compact}
          />
        <% end %>

        <%!-- Show pending saves (being saved to DB) with spinner --%>
        <%= for pending <- @pending_saves do %>
          <.attachment_chip
            id={pending.ref}
            filename={pending.filename}
            size={pending.size}
            type={:saving}
            compact={@compact}
          />
        <% end %>

        <%= if @uploads do %>
          <%!-- Show upload entries that aren't done yet --%>
          <%= for entry <- @uploads.markdown_files.entries, not entry.done? do %>
            <.attachment_chip
              id={entry.ref}
              filename={entry.client_name}
              size={entry.client_size}
              type={:pending}
              progress={entry.progress}
              errors={upload_errors(@uploads.markdown_files, entry)}
              compact={@compact}
            />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :filename, :string, required: true
  attr :size, :integer, required: true
  attr :type, :atom, required: true
  attr :progress, :integer, default: 0
  attr :errors, :list, default: []
  attr :compact, :boolean, default: false

  defp attachment_chip(assigns) do
    bg_style =
      if assigns.type == :pending and assigns.progress < 100,
        do:
          "background: linear-gradient(to right, oklch(var(--p) / 0.3) #{assigns.progress}%, oklch(var(--p) / 0.1) #{assigns.progress}%)"

    assigns =
      assigns
      |> assign(:size_display, format_file_size(assigns.size))
      |> assign(:bg_style, bg_style)
      |> assign(:is_loading, assigns.type in [:pending, :saving])

    ~H"""
    <div
      class={[
        "flex items-center gap-1.5 rounded-md text-xs px-2 py-1",
        @type == :saved && "bg-base-300",
        @type == :saving && "bg-primary/20 border border-primary/30",
        @type == :pending && @progress >= 100 && "bg-primary/20",
        @type == :pending && @progress < 100 && "border border-primary/30"
      ]}
      style={@bg_style}
    >
      <%= if @is_loading do %>
        <span class="loading loading-spinner loading-xs text-primary flex-shrink-0"></span>
      <% else %>
        <.icon name="hero-document-text" class="w-3 h-3 text-primary flex-shrink-0" />
      <% end %>
      <span class="truncate max-w-[150px]" title={@filename}>{@filename}</span>
      <%= if not @compact do %>
        <span class="text-base-content/50 flex-shrink-0">({@size_display})</span>
      <% end %>
      <%= for error <- @errors do %>
        <span class="text-error flex-shrink-0">{error_to_string(error)}</span>
      <% end %>
      <%= if @type in [:saved, :pending] do %>
        <button
          type="button"
          phx-click={if @type == :saved, do: "remove_attachment", else: "cancel_upload"}
          phx-value-id={if @type == :saved, do: @id, else: nil}
          phx-value-ref={if @type == :pending, do: @id, else: nil}
          class="btn btn-circle btn-ghost btn-xs flex-shrink-0 -mr-1"
          aria-label="Remove attachment"
        >
          <.icon name="hero-x-mark" class="w-3 h-3" />
        </button>
      <% end %>
    </div>
    """
  end

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp format_file_size(bytes), do: "#{div(bytes, 1024 * 1024)} MB"

  defp error_to_string(:too_large), do: "File too large"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(:not_accepted), do: "Invalid file type"
  defp error_to_string(_error), do: "Upload error"

  defp processing_files?(assigns) do
    active_upload_count(assigns.uploads) > 0 || assigns.pending_saves != []
  end

  defp active_upload_count(nil), do: 0

  defp active_upload_count(uploads),
    do: Enum.count(uploads.markdown_files.entries, &(not &1.done?))

  @doc """
  Renders the empty chat state with welcome message.
  """
  attr :form, :any, required: true
  attr :is_streaming, :boolean, required: true
  attr :uploads, :any, default: nil
  attr :attachments, :list, default: []
  attr :pending_saves, :list, default: []
  attr :attachments_expanded, :boolean, default: true

  @spec empty_chat_state(map()) :: Phoenix.LiveView.Rendered.t()
  def empty_chat_state(assigns) do
    assigns = assign(assigns, :is_processing_files, processing_files?(assigns))

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
        <.attachment_panel
          attachments={@attachments}
          uploads={@uploads}
          pending_saves={@pending_saves}
          expanded={@attachments_expanded}
        />
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
              aria-label="Message input"
              id="empty-state-input"
              phx-hook="AutoGrowTextarea"
              data-processing-files={@is_processing_files}
            ></textarea>
            <%= if @is_streaming do %>
              <button
                type="button"
                phx-click="stop_streaming"
                class="absolute right-3 bottom-3 btn btn-error btn-sm btn-circle"
                aria-label="Stop generating"
              >
                <.icon name="hero-stop" class="w-4 h-4" />
              </button>
            <% else %>
              <button
                type="submit"
                class={[
                  "absolute right-3 bottom-3 btn btn-sm btn-circle",
                  @is_processing_files && "btn-disabled",
                  not @is_processing_files && "btn-primary"
                ]}
                disabled={@is_processing_files}
                aria-label="Send message"
              >
                <.icon name="hero-arrow-up" class="w-4 h-4" />
              </button>
            <% end %>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
