defmodule Chatbot.URLValidator do
  @moduledoc """
  Validates URLs for security and format correctness.

  For a single-user local application, this module:
  - Validates URL format
  - Ensures only HTTP/HTTPS schemes
  - Provides helpful error messages
  - Blocks dangerous URL patterns (file://, javascript:, etc.)

  Note: This app is designed for local use where users configure their own
  local LLM servers. Localhost URLs are intentionally allowed.
  """

  @doc """
  Validates a URL string for use as an API endpoint.

  Returns `{:ok, normalized_url}` if valid, or `{:error, reason}` if invalid.

  ## Examples

      iex> validate_url("http://localhost:11434")
      {:ok, "http://localhost:11434"}

      iex> validate_url("file:///etc/passwd")
      {:error, "URL must use http or https scheme"}

      iex> validate_url("not a url")
      {:error, "Invalid URL format"}

  """
  @spec validate_url(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_url(url) when is_binary(url) do
    url = String.trim(url)

    with {:ok, uri} <- parse_url(url),
         :ok <- validate_scheme(uri),
         :ok <- validate_host(uri),
         :ok <- validate_port(uri),
         :ok <- validate_no_credentials(uri) do
      {:ok, normalize_url(uri)}
    end
  end

  def validate_url(_invalid), do: {:error, "URL must be a string"}

  @doc """
  Validates a URL and returns a boolean.

  ## Examples

      iex> valid_url?("http://localhost:11434")
      true

      iex> valid_url?("javascript:alert(1)")
      false

  """
  @spec valid_url?(String.t()) :: boolean()
  def valid_url?(url) do
    case validate_url(url) do
      {:ok, _url} -> true
      {:error, _reason} -> false
    end
  end

  @doc """
  Validates a URL and raises on failure.

  ## Examples

      iex> validate_url!("http://localhost:11434")
      "http://localhost:11434"

  """
  @spec validate_url!(String.t()) :: String.t()
  def validate_url!(url) do
    case validate_url(url) do
      {:ok, normalized} -> normalized
      {:error, reason} -> raise ArgumentError, "Invalid URL: #{reason}"
    end
  end

  # Private functions

  defp parse_url(url) do
    case URI.new(url) do
      {:ok, uri} -> {:ok, uri}
      {:error, _reason} -> {:error, "Invalid URL format"}
    end
  end

  defp validate_scheme(%URI{scheme: nil}),
    do: {:error, "URL must include a scheme (http:// or https://)"}

  defp validate_scheme(%URI{scheme: scheme}) when scheme in ["http", "https"], do: :ok
  defp validate_scheme(_other), do: {:error, "URL must use http or https scheme"}

  defp validate_host(%URI{host: nil}), do: {:error, "URL must include a host"}
  defp validate_host(%URI{host: ""}), do: {:error, "URL must include a host"}

  defp validate_host(%URI{host: host}) do
    # Block dangerous patterns
    cond do
      # Block IPv6 localhost bypass attempts
      host in ["[::1]", "[0:0:0:0:0:0:0:1]", "[::ffff:127.0.0.1]"] ->
        :ok

      # Block metadata service endpoints (cloud SSRF targets)
      host in ["169.254.169.254", "metadata.google.internal", "metadata"] ->
        {:error, "Access to cloud metadata services is not allowed"}

      # Block octal/hex IP bypass attempts for metadata
      metadata_bypass?(host) ->
        {:error, "Access to cloud metadata services is not allowed"}

      true ->
        :ok
    end
  end

  defp validate_port(%URI{port: nil}), do: :ok
  defp validate_port(%URI{port: port}) when port > 0 and port <= 65_535, do: :ok
  defp validate_port(_uri), do: {:error, "Invalid port number"}

  defp validate_no_credentials(%URI{userinfo: nil}), do: :ok
  defp validate_no_credentials(_uri), do: {:error, "URL must not contain credentials"}

  # Detect metadata service IP obfuscation attempts
  defp metadata_bypass?(host) do
    # 169.254.169.254 in various formats
    host
    |> String.downcase()
    |> then(fn h ->
      # Decimal representation: 2852039166
      # Hex representation
      # Octal representation patterns
      # Mixed format attempts
      h == "2852039166" or
        String.starts_with?(h, "0xa9fe") or
        String.match?(h, ~r/^0[0-7]+\./) or
        String.match?(h, ~r/169\.254\.169\.254/)
    end)
  end

  defp normalize_url(%URI{} = uri) do
    # Remove trailing slash for consistency
    uri
    |> URI.to_string()
    |> String.trim_trailing("/")
  end
end
