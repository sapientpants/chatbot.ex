defmodule ChatbotWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  For form components, see `FormComponents`.
  For modal dialogs, see `ModalComponents`.
  For data display (tables, lists), see `DataComponents`.

  The foundation for styling is Tailwind CSS augmented with daisyUI.

  References:
    * [daisyUI](https://daisyui.com/docs/intro/)
    * [Tailwind CSS](https://tailwindcss.com)
    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: ChatbotWeb.Gettext

  alias Phoenix.LiveView.JS

  # Re-export components from extracted modules for backwards compatibility
  defdelegate simple_form(assigns), to: ChatbotWeb.FormComponents
  defdelegate input(assigns), to: ChatbotWeb.FormComponents
  defdelegate modal(assigns), to: ChatbotWeb.ModalComponents
  defdelegate show_modal(id), to: ChatbotWeb.ModalComponents
  defdelegate hide_modal(id), to: ChatbotWeb.ModalComponents
  defdelegate header(assigns), to: ChatbotWeb.DataComponents
  defdelegate table(assigns), to: ChatbotWeb.DataComponents
  defdelegate list(assigns), to: ChatbotWeb.DataComponents

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  @spec flash(map()) :: Phoenix.LiveView.Rendered.t()
  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}
    variant_class = Map.fetch!(variants, assigns[:variant])

    assigns =
      assign(assigns, :btn_class, Enum.reject(["btn", variant_class, assigns[:class]], &is_nil/1))

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@btn_class} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button class={@btn_class} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  @spec icon(map()) :: Phoenix.LiveView.Rendered.t()
  def icon(%{name: "hero-" <> _icon_name} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders markdown content as HTML.

  Uses Earmark to parse markdown and render it with appropriate styling.
  The content is sanitized with HtmlSanitizeEx before rendering.

  ## Examples

      <.markdown content={@message.content} />
  """
  attr :content, :string, required: true
  attr :class, :string, default: nil

  # sobelow_skip ["XSS.Raw"]
  @spec markdown(map()) :: Phoenix.LiveView.Rendered.t()
  def markdown(assigns) do
    html =
      case Earmark.as_html(assigns.content, code_class_prefix: "language-", smartypants: false) do
        {:ok, html_string, _warnings} ->
          html_string |> HtmlSanitizeEx.markdown_html() |> Phoenix.HTML.raw()

        {:error, _html, _errors} ->
          Phoenix.HTML.raw("<p>Error rendering markdown</p>")
      end

    assigns = assign(assigns, :html, html)

    ~H"""
    <div class={[
      "prose prose-sm max-w-full dark:prose-invert",
      "prose-p:my-3 prose-p:leading-relaxed",
      "prose-pre:bg-base-300/80 prose-pre:text-base-content prose-pre:rounded-xl prose-pre:p-4 prose-pre:overflow-x-auto prose-pre:my-5 prose-pre:border prose-pre:border-base-content/10 prose-pre:shadow-sm",
      "prose-code:bg-base-300 prose-code:px-1.5 prose-code:py-0.5 prose-code:rounded prose-code:text-sm prose-code:before:content-none prose-code:after:content-none",
      "prose-ul:my-3 prose-ul:list-disc prose-ul:pl-5 prose-ol:my-3 prose-ol:list-decimal prose-ol:pl-5 prose-li:my-1.5 prose-li:marker:text-base-content/60",
      "prose-headings:font-semibold prose-headings:text-base-content prose-h1:text-xl prose-h1:mt-6 prose-h1:mb-3 prose-h2:text-lg prose-h2:mt-5 prose-h2:mb-2 prose-h3:text-base prose-h3:mt-4 prose-h3:mb-2",
      "prose-a:text-primary prose-a:no-underline hover:prose-a:underline",
      "prose-blockquote:border-l-primary prose-blockquote:not-italic prose-blockquote:my-4 prose-blockquote:pl-4",
      "prose-strong:font-semibold prose-strong:text-base-content",
      "prose-hr:my-6",
      @class
    ]}>
      {@html}
    </div>
    """
  end

  ## JS Commands

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

  @doc "Translates an error message using gettext."
  @spec translate_error({String.t(), keyword()}) :: String.t()
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(ChatbotWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ChatbotWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc "Translates the errors for a field from a keyword list of errors."
  @spec translate_errors(keyword(), atom()) :: [String.t()]
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
