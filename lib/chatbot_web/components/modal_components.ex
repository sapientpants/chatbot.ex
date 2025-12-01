defmodule ChatbotWeb.ModalComponents do
  @moduledoc """
  Modal dialog components and JS animation helpers.
  """
  use Phoenix.Component
  use Gettext, backend: ChatbotWeb.Gettext

  import ChatbotWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal dialog.

  ## Examples

      <.modal id="confirm-modal" show={@show_modal}>
        <p>Are you sure?</p>
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}

  slot :inner_block, required: true

  @spec modal(map()) :: Phoenix.LiveView.Rendered.t()
  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-black/60 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center p-4">
          <div class="w-full max-w-lg p-6 relative rounded-xl bg-base-100 shadow-xl border border-base-content/10">
            <button
              phx-click={JS.exec("data-cancel", to: "##{@id}")}
              type="button"
              class="absolute top-4 right-4 text-base-content/50 hover:text-base-content"
              aria-label={gettext("close")}
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
            <div id={"#{@id}-content"}>
              {render_slot(@inner_block)}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc "Shows a modal by ID."
  @spec show_modal(String.t()) :: JS.t()
  def show_modal(id) when is_binary(id) do
    %JS{}
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-content",
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.focus_first(to: "##{id}-content")
  end

  @doc "Hides a modal by ID."
  @spec hide_modal(String.t()) :: JS.t()
  def hide_modal(id) when is_binary(id) do
    %JS{}
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-content",
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.pop_focus()
  end

  @doc "Shows an element with animation transition."
  @spec show(map(), String.t()) :: map()
  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  @doc "Hides an element with animation transition."
  @spec hide(map(), String.t()) :: map()
  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end
end
