defmodule Chatbot.MCP.ArgumentSanitizer do
  @moduledoc """
  Sanitizes and validates MCP tool arguments before execution.

  Provides security and correctness validation for tool arguments:
  - Type validation and coercion
  - Size limits enforcement
  - Extra property removal
  - Required field validation
  - String value sanitization

  ## Configuration

      config :chatbot, :mcp,
        max_string_arg_length: 100_000,
        max_argument_depth: 10,
        max_array_length: 1000
  """

  require Logger

  @default_max_string_length 100_000
  @default_max_depth 10
  @default_max_array_length 1_000

  @type sanitize_result :: {:ok, map()} | {:error, String.t()}

  @doc """
  Sanitizes arguments against the tool's input schema.

  Returns sanitized arguments with:
  - Type coercion applied where safe
  - Extra properties removed (if additionalProperties: false)
  - Size limits enforced
  - Required fields validated

  ## Examples

      iex> schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
      iex> sanitize(%{"name" => "test"}, schema)
      {:ok, %{"name" => "test"}}

      iex> sanitize(%{"name" => 123}, schema)
      {:ok, %{"name" => "123"}}  # Coerced to string

  """
  @spec sanitize(map() | String.t() | nil, map() | nil) :: sanitize_result()
  def sanitize(nil, _schema), do: {:ok, %{}}
  def sanitize(args, nil), do: {:ok, ensure_map(args)}

  def sanitize(args, schema) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} -> sanitize(decoded, schema)
      {:error, _reason} -> {:error, "Invalid JSON in arguments"}
    end
  end

  def sanitize(args, schema) when is_map(args) do
    with :ok <- validate_depth(args, 0) do
      sanitize_value(args, schema, [])
    end
  end

  def sanitize(_args, _schema), do: {:error, "Arguments must be a map or JSON string"}

  @doc """
  Validates that all required fields are present.
  """
  @spec validate_required(map(), map()) :: :ok | {:error, String.t()}
  def validate_required(args, schema) do
    required = Map.get(schema, "required", [])

    missing =
      Enum.filter(required, fn field ->
        not Map.has_key?(args, field)
      end)

    if missing == [] do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp sanitize_value(value, schema, path) when is_map(value) and is_map(schema) do
    type = Map.get(schema, "type", "object")

    case type do
      "object" -> sanitize_object(value, schema, path)
      "string" -> {:ok, to_string_safe(value)}
      "number" -> coerce_number(value, path)
      "integer" -> coerce_integer(value, path)
      "boolean" -> coerce_boolean(value, path)
      "array" -> sanitize_array(value, schema, path)
      _other -> {:ok, value}
    end
  end

  defp sanitize_value(value, schema, path) when is_list(value) do
    type = Map.get(schema, "type", "array")

    case type do
      "array" -> sanitize_array(value, schema, path)
      "string" -> {:ok, Jason.encode!(value)}
      _other -> {:ok, value}
    end
  end

  defp sanitize_value(value, schema, path) when is_binary(value) do
    type = Map.get(schema, "type", "string")

    case type do
      "string" -> sanitize_string(value, path)
      "number" -> coerce_number(value, path)
      "integer" -> coerce_integer(value, path)
      "boolean" -> coerce_boolean(value, path)
      "object" -> parse_json_string(value, schema, path)
      "array" -> {:error, "Expected array at #{format_path(path)}, got string"}
      _other -> sanitize_string(value, path)
    end
  end

  defp sanitize_value(value, schema, _path) when is_number(value) do
    type = Map.get(schema, "type", "number")

    case type do
      "string" -> {:ok, to_string(value)}
      "integer" when is_integer(value) -> {:ok, value}
      "integer" -> {:ok, round(value)}
      "boolean" when value == 1 -> {:ok, true}
      "boolean" when value == 0 -> {:ok, false}
      "boolean" -> {:ok, value != 0}
      _other -> {:ok, value}
    end
  end

  defp sanitize_value(value, schema, _path) when is_boolean(value) do
    type = Map.get(schema, "type", "boolean")

    case type do
      "string" -> {:ok, to_string(value)}
      _other -> {:ok, value}
    end
  end

  defp sanitize_value(nil, schema, _path) do
    if Map.get(schema, "nullable", false) do
      {:ok, nil}
    else
      {:ok, Map.get(schema, "default")}
    end
  end

  # Handle atoms - convert to string when schema expects string
  defp sanitize_value(value, schema, _path) when is_atom(value) and not is_nil(value) do
    type = Map.get(schema, "type", "string")

    case type do
      "string" -> {:ok, Atom.to_string(value)}
      _other -> {:ok, value}
    end
  end

  defp sanitize_value(value, _schema, _path), do: {:ok, value}

  defp sanitize_object(obj, schema, path) do
    properties = Map.get(schema, "properties", %{})
    additional_properties = Map.get(schema, "additionalProperties", true)

    # Filter out extra properties if not allowed
    filtered_obj =
      if additional_properties == false do
        Map.take(obj, Map.keys(properties))
      else
        obj
      end

    # Sanitize each property
    # Note: We prepend to path and reverse when formatting for O(1) path building
    result =
      Enum.reduce_while(filtered_obj, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
        prop_schema = Map.get(properties, key, %{})
        prop_path = [key | path]

        case sanitize_value(value, prop_schema, prop_path) do
          {:ok, sanitized} -> {:cont, {:ok, Map.put(acc, key, sanitized)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with {:ok, sanitized} <- result do
      case validate_required(sanitized, schema) do
        :ok -> {:ok, sanitized}
        error -> error
      end
    end
  end

  defp sanitize_array(arr, schema, path) when is_list(arr) do
    max_length = config(:max_array_length) || @default_max_array_length

    if length(arr) > max_length do
      {:error, "Array at #{format_path(path)} exceeds max length of #{max_length}"}
    else
      items_schema = Map.get(schema, "items", %{})

      result =
        arr
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, []}, fn {item, idx}, {:ok, acc} ->
          # Prepend to path (reversed when formatting)
          item_path = ["[#{idx}]" | path]

          case sanitize_value(item, items_schema, item_path) do
            {:ok, sanitized} -> {:cont, {:ok, [sanitized | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case result do
        {:ok, items} -> {:ok, Enum.reverse(items)}
        error -> error
      end
    end
  end

  defp sanitize_array(value, _schema, path) do
    {:error, "Expected array at #{format_path(path)}, got #{typeof(value)}"}
  end

  defp sanitize_string(value, path) when is_binary(value) do
    max_length = config(:max_string_arg_length) || @default_max_string_length

    if byte_size(value) > max_length do
      {:error, "String at #{format_path(path)} exceeds max length of #{max_length} bytes"}
    else
      {:ok, value}
    end
  end

  defp coerce_number(value, _path) when is_number(value), do: {:ok, value}

  defp coerce_number(value, path) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> {:ok, num}
      {num, _rest} -> {:ok, num}
      :error -> {:error, "Cannot convert '#{truncate(value)}' to number at #{format_path(path)}"}
    end
  end

  defp coerce_number(value, path) do
    {:error, "Cannot convert #{typeof(value)} to number at #{format_path(path)}"}
  end

  defp coerce_integer(value, _path) when is_integer(value), do: {:ok, value}
  defp coerce_integer(value, _path) when is_float(value), do: {:ok, round(value)}

  defp coerce_integer(value, path) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} -> {:ok, num}
      {num, _rest} -> {:ok, num}
      :error -> {:error, "Cannot convert '#{truncate(value)}' to integer at #{format_path(path)}"}
    end
  end

  defp coerce_integer(value, path) do
    {:error, "Cannot convert #{typeof(value)} to integer at #{format_path(path)}"}
  end

  defp coerce_boolean(value, _path) when is_boolean(value), do: {:ok, value}
  defp coerce_boolean("true", _path), do: {:ok, true}
  defp coerce_boolean("false", _path), do: {:ok, false}
  defp coerce_boolean("1", _path), do: {:ok, true}
  defp coerce_boolean("0", _path), do: {:ok, false}
  defp coerce_boolean(1, _path), do: {:ok, true}
  defp coerce_boolean(0, _path), do: {:ok, false}

  defp coerce_boolean(value, path) do
    {:error, "Cannot convert #{typeof(value)} to boolean at #{format_path(path)}"}
  end

  defp parse_json_string(value, schema, path) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) ->
        sanitize_value(decoded, schema, path)

      {:ok, _other} ->
        {:error, "Expected JSON object at #{format_path(path)}"}

      {:error, _reason} ->
        {:error, "Invalid JSON at #{format_path(path)}"}
    end
  end

  defp validate_depth(_value, depth) when depth > @default_max_depth do
    {:error, "Argument nesting exceeds maximum depth of #{@default_max_depth}"}
  end

  defp validate_depth(value, depth) when is_map(value) do
    validate_depth_for_collection(Map.values(value), depth)
  end

  defp validate_depth(value, depth) when is_list(value) do
    validate_depth_for_collection(value, depth)
  end

  defp validate_depth(_value, _depth), do: :ok

  # Helper to validate depth for both maps and lists
  defp validate_depth_for_collection(items, depth) do
    max_depth = config(:max_argument_depth) || @default_max_depth

    if depth > max_depth do
      {:error, "Argument nesting exceeds maximum depth of #{max_depth}"}
    else
      Enum.reduce_while(items, :ok, fn item, :ok ->
        case validate_depth(item, depth + 1) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp ensure_map(args) when is_map(args), do: args

  defp ensure_map(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp ensure_map(_args), do: %{}

  defp to_string_safe(value) when is_binary(value), do: value
  defp to_string_safe(value) when is_number(value), do: to_string(value)
  defp to_string_safe(value) when is_atom(value), do: to_string(value)
  defp to_string_safe(value), do: Jason.encode!(value)

  # Path is stored in reverse order for O(1) prepending, so we reverse when formatting
  defp format_path([]), do: "root"
  defp format_path(path), do: path |> Enum.reverse() |> Enum.join(".")

  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_integer(value), do: "integer"
  defp typeof(value) when is_float(value), do: "float"
  defp typeof(value) when is_boolean(value), do: "boolean"
  defp typeof(value) when is_list(value), do: "array"
  defp typeof(value) when is_map(value), do: "object"
  defp typeof(nil), do: "null"
  defp typeof(_value), do: "unknown"

  defp truncate(value) when is_binary(value) do
    if byte_size(value) > 50 do
      String.slice(value, 0, 50) <> "..."
    else
      value
    end
  end

  defp truncate(value), do: inspect(value)

  defp config(key) do
    Application.get_env(:chatbot, :mcp, [])[key]
  end
end
