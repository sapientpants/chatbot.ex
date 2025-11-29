defmodule Chatbot.PII do
  @moduledoc """
  Utilities for handling Personally Identifiable Information (PII).

  Provides functions to mask sensitive data like email addresses
  before logging or displaying in non-secure contexts.
  """

  @doc """
  Masks an email address for safe logging.

  Preserves the first character of the local part and domain,
  replacing the rest with asterisks.

  ## Examples

      iex> Chatbot.PII.mask_email("john.doe@example.com")
      "j***@e***.com"

      iex> Chatbot.PII.mask_email("a@b.co")
      "a***@b***.co"

      iex> Chatbot.PII.mask_email(nil)
      "[no email]"

  """
  @spec mask_email(String.t() | nil) :: String.t()
  def mask_email(nil), do: "[no email]"
  def mask_email(""), do: "[no email]"

  def mask_email(email) when is_binary(email) do
    case String.split(email, "@") do
      [local, domain] ->
        masked_local = mask_string(local)
        masked_domain = mask_domain(domain)
        "#{masked_local}@#{masked_domain}"

      _other ->
        "[invalid email]"
    end
  end

  defp mask_string(str) when byte_size(str) <= 1, do: str <> "***"

  defp mask_string(str) do
    first = String.first(str)
    "#{first}***"
  end

  defp mask_domain(domain) do
    case String.split(domain, ".") do
      [name | [_first_part | _rest_parts] = rest] ->
        masked_name = mask_string(name)
        tld = Enum.join(rest, ".")
        "#{masked_name}.#{tld}"

      _other ->
        mask_string(domain)
    end
  end
end
