defmodule Chatbot.SecurityLog do
  @moduledoc """
  Structured security logging for audit and incident response.

  Provides consistent logging for security-relevant events:
  - Authentication failures
  - Rate limiting triggers
  - SSRF/URL validation failures
  - MCP tool execution
  - Authorization failures

  ## Usage

      SecurityLog.auth_failure("user@example.com", :invalid_password, %{ip: "1.2.3.4"})
      SecurityLog.rate_limit_exceeded(user_id, :message, %{count: 10})
      SecurityLog.ssrf_blocked(url, :private_ip, %{ip: "10.0.0.1"})

  ## Log Format

  All security logs include:
  - `event` - The security event type
  - `timestamp` - ISO8601 timestamp
  - `severity` - Log level (info, warning, error)
  - Event-specific metadata

  """

  require Logger

  @type event_type ::
          :auth_failure
          | :auth_success
          | :rate_limit_exceeded
          | :ssrf_blocked
          | :url_validation_failed
          | :mcp_tool_executed
          | :mcp_tool_failed
          | :authorization_failure
          | :suspicious_activity
          | :session_created
          | :session_invalidated

  @doc """
  Logs an authentication failure.
  """
  @spec auth_failure(String.t() | nil, atom(), map()) :: :ok
  def auth_failure(identifier, reason, metadata \\ %{}) do
    log(:warning, :auth_failure, %{
      identifier: mask_identifier(identifier),
      reason: reason,
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs a successful authentication.
  Note: Uses warning level to ensure security events are captured.
  """
  @spec auth_success(String.t(), map()) :: :ok
  def auth_success(user_id, metadata \\ %{}) do
    log(:warning, :auth_success, %{
      user_id: user_id,
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs a rate limit being exceeded.
  """
  @spec rate_limit_exceeded(String.t() | nil, atom(), map()) :: :ok
  def rate_limit_exceeded(identifier, limit_type, metadata \\ %{}) do
    log(:warning, :rate_limit_exceeded, %{
      identifier: mask_identifier(identifier),
      limit_type: limit_type,
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs an SSRF attempt being blocked.
  """
  @spec ssrf_blocked(String.t(), atom(), map()) :: :ok
  def ssrf_blocked(url, reason, metadata \\ %{}) do
    log(:warning, :ssrf_blocked, %{
      url: mask_url(url),
      reason: reason,
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs a URL validation failure.
  """
  @spec url_validation_failed(String.t(), atom(), map()) :: :ok
  def url_validation_failed(url, reason, metadata \\ %{}) do
    log(:warning, :url_validation_failed, %{
      url: mask_url(url),
      reason: reason,
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs a successful MCP tool execution.
  Note: Uses warning level to ensure security audit trail is captured.
  """
  @spec mcp_tool_executed(String.t(), String.t(), map()) :: :ok
  def mcp_tool_executed(user_id, tool_name, metadata \\ %{}) do
    log(:warning, :mcp_tool_executed, %{
      user_id: user_id,
      tool_name: tool_name,
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs an MCP tool execution failure.
  """
  @spec mcp_tool_failed(String.t(), String.t(), String.t(), map()) :: :ok
  def mcp_tool_failed(user_id, tool_name, error, metadata \\ %{}) do
    log(:warning, :mcp_tool_failed, %{
      user_id: user_id,
      tool_name: tool_name,
      error: truncate(error, 500),
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs an authorization failure.
  """
  @spec authorization_failure(String.t() | nil, String.t(), map()) :: :ok
  def authorization_failure(user_id, resource, metadata \\ %{}) do
    log(:warning, :authorization_failure, %{
      user_id: user_id,
      resource: resource,
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs suspicious activity that may indicate an attack.
  """
  @spec suspicious_activity(atom(), map()) :: :ok
  def suspicious_activity(activity_type, metadata \\ %{}) do
    log(:warning, :suspicious_activity, %{
      activity_type: activity_type,
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs a new session being created.
  Note: Uses warning level to ensure security audit trail is captured.
  """
  @spec session_created(String.t(), map()) :: :ok
  def session_created(user_id, metadata \\ %{}) do
    log(:warning, :session_created, %{
      user_id: user_id,
      metadata: sanitize_metadata(metadata)
    })
  end

  @doc """
  Logs a session being invalidated.
  Note: Uses warning level to ensure security audit trail is captured.
  """
  @spec session_invalidated(String.t(), atom(), map()) :: :ok
  def session_invalidated(user_id, reason, metadata \\ %{}) do
    log(:warning, :session_invalidated, %{
      user_id: user_id,
      reason: reason,
      metadata: sanitize_metadata(metadata)
    })
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp log(level, event, data) do
    log_entry = %{
      event: event,
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      data: data
    }

    message = "[SECURITY] #{event}: #{Jason.encode!(log_entry)}"

    case level do
      :info -> Logger.info(message)
      :warning -> Logger.warning(message)
      :error -> Logger.error(message)
    end

    :ok
  end

  # Mask email addresses for privacy
  defp mask_identifier(nil), do: nil

  defp mask_identifier(identifier) when is_binary(identifier) do
    if String.contains?(identifier, "@") do
      mask_email(identifier)
    else
      # For non-email identifiers, show first 4 chars
      if String.length(identifier) > 8 do
        String.slice(identifier, 0, 4) <> "****"
      else
        "****"
      end
    end
  end

  defp mask_email(email) do
    case String.split(email, "@") do
      [local, domain] ->
        masked_local =
          if String.length(local) > 2 do
            String.first(local) <> "***" <> String.last(local)
          else
            "***"
          end

        "#{masked_local}@#{domain}"

      _other ->
        "***@***"
    end
  end

  # Mask sensitive parts of URLs
  defp mask_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host, scheme: scheme} when is_binary(host) ->
        "#{scheme}://#{host}/***"

      _invalid_uri ->
        "***"
    end
  end

  defp mask_url(_other), do: "***"

  # Remove sensitive fields from metadata
  defp sanitize_metadata(metadata) when is_map(metadata) do
    sensitive_keys =
      ~w(password token secret key api_key authorization)a ++
        ~w(password token secret key api_key authorization)

    metadata
    |> Map.drop(sensitive_keys)
    |> Map.new(fn {k, v} -> {k, sanitize_value(v)} end)
  end

  defp sanitize_metadata(_other), do: %{}

  defp sanitize_value(value) when is_binary(value), do: truncate(value, 200)
  defp sanitize_value(value) when is_map(value), do: sanitize_metadata(value)
  defp sanitize_value(value) when is_list(value), do: Enum.take(value, 10)
  defp sanitize_value(value), do: value

  defp truncate(string, max_length) when is_binary(string) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length) <> "..."
    else
      string
    end
  end

  defp truncate(other, _max_length), do: inspect(other)
end
