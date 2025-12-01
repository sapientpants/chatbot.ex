defmodule ChatbotWeb.Live.Chat.InputComponents do
  @moduledoc """
  Components for chat input forms and empty states.
  """
  use Phoenix.Component

  import ChatbotWeb.CoreComponents

  @doc """
  Renders the message input form.
  """
  attr :form, :any, required: true
  attr :is_streaming, :boolean, required: true
  attr :id, :string, default: "message-input"

  @spec message_input_form(map()) :: Phoenix.LiveView.Rendered.t()
  def message_input_form(assigns) do
    ~H"""
    <div class="border-t border-base-300 bg-base-100 p-4">
      <div class="max-w-3xl mx-auto">
        <.form for={@form} phx-submit="send_message" aria-label="Send message">
          <div class="relative flex items-end gap-2 bg-base-200 rounded-2xl p-2 focus-within:ring-2 focus-within:ring-primary focus-within:ring-offset-2 focus-within:ring-offset-base-100 transition-shadow">
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

  @doc """
  Renders the empty chat state with welcome message.
  """
  attr :form, :any, required: true
  attr :is_streaming, :boolean, required: true

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
          I can help with coding, writing, analysis, brainstorming, and much more. Just type your message below.
        </p>
      </div>
      <div class="w-full max-w-2xl">
        <.form for={@form} phx-submit="send_message" aria-label="Send message">
          <div class="relative">
            <textarea
              name="message[content]"
              placeholder="Type your message..."
              rows="3"
              class="textarea textarea-bordered w-full text-base resize-none pr-14 focus:textarea-primary focus:outline-none"
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
