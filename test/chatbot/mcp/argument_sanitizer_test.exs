defmodule Chatbot.MCP.ArgumentSanitizerTest do
  use ExUnit.Case, async: true

  alias Chatbot.MCP.ArgumentSanitizer

  describe "sanitize/2" do
    test "returns empty map for nil args" do
      assert {:ok, %{}} = ArgumentSanitizer.sanitize(nil, %{})
    end

    test "returns map as-is when schema is nil" do
      args = %{"name" => "test"}
      assert {:ok, ^args} = ArgumentSanitizer.sanitize(args, nil)
    end

    test "parses JSON string arguments" do
      json = ~s({"name": "test"})
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
      assert {:ok, %{"name" => "test"}} = ArgumentSanitizer.sanitize(json, schema)
    end

    test "returns error for invalid JSON" do
      assert {:error, "Invalid JSON in arguments"} =
               ArgumentSanitizer.sanitize("not json", %{})
    end

    test "returns error for non-map arguments" do
      assert {:error, "Arguments must be a map or JSON string"} =
               ArgumentSanitizer.sanitize(123, %{})
    end

    test "handles empty JSON string returning empty map" do
      json = ~s({})
      schema = %{"type" => "object"}
      assert {:ok, %{}} = ArgumentSanitizer.sanitize(json, schema)
    end
  end

  describe "type coercion - map to other types" do
    test "converts map to string via JSON encoding when type is string" do
      schema = %{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "string"}}
      }

      args = %{"data" => %{"nested" => "value"}}

      assert {:ok, %{"data" => json}} = ArgumentSanitizer.sanitize(args, schema)
      assert is_binary(json)
    end

    test "handles map with type number returns error" do
      schema = %{
        "type" => "object",
        "properties" => %{"count" => %{"type" => "number"}}
      }

      args = %{"count" => %{"nested" => 1}}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "Cannot convert"
    end

    test "handles map with type integer returns error" do
      schema = %{
        "type" => "object",
        "properties" => %{"count" => %{"type" => "integer"}}
      }

      args = %{"count" => %{"nested" => 1}}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "Cannot convert"
    end

    test "handles map with type boolean returns error" do
      schema = %{
        "type" => "object",
        "properties" => %{"flag" => %{"type" => "boolean"}}
      }

      args = %{"flag" => %{"nested" => true}}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "Cannot convert"
    end

    test "handles map with unknown type passes through" do
      schema = %{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "unknown"}}
      }

      args = %{"data" => %{"nested" => "value"}}

      assert {:ok, %{"data" => %{"nested" => "value"}}} =
               ArgumentSanitizer.sanitize(args, schema)
    end
  end

  describe "type coercion - list handling" do
    test "converts list to JSON string when type is string" do
      schema = %{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "string"}}
      }

      args = %{"data" => [1, 2, 3]}

      assert {:ok, %{"data" => "[1,2,3]"}} = ArgumentSanitizer.sanitize(args, schema)
    end

    test "handles list with unknown type passes through" do
      schema = %{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "unknown"}}
      }

      args = %{"data" => [1, 2, 3]}

      assert {:ok, %{"data" => [1, 2, 3]}} = ArgumentSanitizer.sanitize(args, schema)
    end
  end

  describe "type coercion - string to object" do
    test "parses JSON string as object when type is object" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "config" => %{
            "type" => "object",
            "properties" => %{"key" => %{"type" => "string"}}
          }
        }
      }

      args = %{"config" => ~s({"key": "value"})}

      assert {:ok, %{"config" => %{"key" => "value"}}} =
               ArgumentSanitizer.sanitize(args, schema)
    end

    test "returns error for invalid JSON string when type is object" do
      schema = %{
        "type" => "object",
        "properties" => %{"config" => %{"type" => "object"}}
      }

      args = %{"config" => "not json"}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "Invalid JSON"
    end

    test "returns error for JSON array when expecting object" do
      schema = %{
        "type" => "object",
        "properties" => %{"config" => %{"type" => "object"}}
      }

      args = %{"config" => "[1,2,3]"}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "Expected JSON object"
    end

    test "handles string with unknown type as string" do
      schema = %{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "unknown"}}
      }

      args = %{"data" => "test"}

      assert {:ok, %{"data" => "test"}} = ArgumentSanitizer.sanitize(args, schema)
    end
  end

  describe "type coercion - boolean handling" do
    test "converts boolean to string when type is string" do
      schema = %{
        "type" => "object",
        "properties" => %{"flag" => %{"type" => "string"}}
      }

      assert {:ok, %{"flag" => "true"}} =
               ArgumentSanitizer.sanitize(%{"flag" => true}, schema)

      assert {:ok, %{"flag" => "false"}} =
               ArgumentSanitizer.sanitize(%{"flag" => false}, schema)
    end

    test "passes boolean through when type is boolean" do
      schema = %{
        "type" => "object",
        "properties" => %{"flag" => %{"type" => "boolean"}}
      }

      assert {:ok, %{"flag" => true}} =
               ArgumentSanitizer.sanitize(%{"flag" => true}, schema)
    end

    test "passes boolean through when type is unknown" do
      schema = %{
        "type" => "object",
        "properties" => %{"flag" => %{"type" => "unknown"}}
      }

      assert {:ok, %{"flag" => true}} =
               ArgumentSanitizer.sanitize(%{"flag" => true}, schema)
    end
  end

  describe "type coercion - number to boolean" do
    test "coerces non-zero number to boolean true" do
      schema = %{
        "type" => "object",
        "properties" => %{"enabled" => %{"type" => "boolean"}}
      }

      assert {:ok, %{"enabled" => true}} =
               ArgumentSanitizer.sanitize(%{"enabled" => 42}, schema)
    end

    test "coerces 0 to boolean false" do
      schema = %{
        "type" => "object",
        "properties" => %{"enabled" => %{"type" => "boolean"}}
      }

      assert {:ok, %{"enabled" => false}} =
               ArgumentSanitizer.sanitize(%{"enabled" => 0}, schema)
    end
  end

  describe "type coercion" do
    test "coerces number to string" do
      schema = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}}
      }

      assert {:ok, %{"name" => "123"}} =
               ArgumentSanitizer.sanitize(%{"name" => 123}, schema)
    end

    test "coerces string to number" do
      schema = %{
        "type" => "object",
        "properties" => %{"count" => %{"type" => "number"}}
      }

      assert {:ok, %{"count" => 42.0}} =
               ArgumentSanitizer.sanitize(%{"count" => "42"}, schema)
    end

    test "coerces string to integer" do
      schema = %{
        "type" => "object",
        "properties" => %{"count" => %{"type" => "integer"}}
      }

      assert {:ok, %{"count" => 42}} =
               ArgumentSanitizer.sanitize(%{"count" => "42"}, schema)
    end

    test "coerces float to integer by rounding" do
      schema = %{
        "type" => "object",
        "properties" => %{"count" => %{"type" => "integer"}}
      }

      # round(42.7) = 43 (standard rounding)
      assert {:ok, %{"count" => 43}} =
               ArgumentSanitizer.sanitize(%{"count" => 42.7}, schema)

      # round(42.4) = 42
      assert {:ok, %{"count" => 42}} =
               ArgumentSanitizer.sanitize(%{"count" => 42.4}, schema)
    end

    test "coerces string 'true' to boolean" do
      schema = %{
        "type" => "object",
        "properties" => %{"enabled" => %{"type" => "boolean"}}
      }

      assert {:ok, %{"enabled" => true}} =
               ArgumentSanitizer.sanitize(%{"enabled" => "true"}, schema)
    end

    test "coerces string 'false' to boolean" do
      schema = %{
        "type" => "object",
        "properties" => %{"enabled" => %{"type" => "boolean"}}
      }

      assert {:ok, %{"enabled" => false}} =
               ArgumentSanitizer.sanitize(%{"enabled" => "false"}, schema)
    end

    test "coerces 1 to boolean true" do
      schema = %{
        "type" => "object",
        "properties" => %{"enabled" => %{"type" => "boolean"}}
      }

      assert {:ok, %{"enabled" => true}} =
               ArgumentSanitizer.sanitize(%{"enabled" => 1}, schema)
    end

    test "returns error for invalid number coercion" do
      schema = %{
        "type" => "object",
        "properties" => %{"count" => %{"type" => "number"}}
      }

      assert {:error, "Cannot convert 'not a number' to number at count"} =
               ArgumentSanitizer.sanitize(%{"count" => "not a number"}, schema)
    end

    test "returns error for invalid boolean coercion" do
      schema = %{
        "type" => "object",
        "properties" => %{"enabled" => %{"type" => "boolean"}}
      }

      assert {:error, "Cannot convert string to boolean at enabled"} =
               ArgumentSanitizer.sanitize(%{"enabled" => "maybe"}, schema)
    end
  end

  describe "extra property removal" do
    test "removes extra properties when additionalProperties is false" do
      schema = %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "name" => %{"type" => "string"}
        }
      }

      args = %{"name" => "test", "extra" => "should be removed"}

      assert {:ok, %{"name" => "test"}} = ArgumentSanitizer.sanitize(args, schema)
    end

    test "keeps extra properties when additionalProperties is true" do
      schema = %{
        "type" => "object",
        "additionalProperties" => true,
        "properties" => %{
          "name" => %{"type" => "string"}
        }
      }

      args = %{"name" => "test", "extra" => "should be kept"}

      assert {:ok, result} = ArgumentSanitizer.sanitize(args, schema)
      assert result["name"] == "test"
      assert result["extra"] == "should be kept"
    end

    test "keeps extra properties by default" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"}
        }
      }

      args = %{"name" => "test", "extra" => "should be kept"}

      assert {:ok, result} = ArgumentSanitizer.sanitize(args, schema)
      assert result["extra"] == "should be kept"
    end
  end

  describe "required field validation" do
    test "passes when all required fields are present" do
      schema = %{
        "type" => "object",
        "required" => ["name", "email"],
        "properties" => %{
          "name" => %{"type" => "string"},
          "email" => %{"type" => "string"}
        }
      }

      args = %{"name" => "test", "email" => "test@example.com"}
      assert {:ok, _sanitized} = ArgumentSanitizer.sanitize(args, schema)
    end

    test "returns error when required field is missing" do
      schema = %{
        "type" => "object",
        "required" => ["name", "email"],
        "properties" => %{
          "name" => %{"type" => "string"},
          "email" => %{"type" => "string"}
        }
      }

      args = %{"name" => "test"}

      assert {:error, "Missing required fields: email"} =
               ArgumentSanitizer.sanitize(args, schema)
    end

    test "returns error listing all missing required fields" do
      schema = %{
        "type" => "object",
        "required" => ["name", "email", "age"],
        "properties" => %{
          "name" => %{"type" => "string"},
          "email" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        }
      }

      args = %{}
      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "Missing required fields:"
      assert msg =~ "name"
      assert msg =~ "email"
      assert msg =~ "age"
    end
  end

  describe "array handling" do
    test "sanitizes array items" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          }
        }
      }

      args = %{"tags" => [1, 2, 3]}

      assert {:ok, %{"tags" => ["1", "2", "3"]}} =
               ArgumentSanitizer.sanitize(args, schema)
    end

    test "returns error when array exceeds max length" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "items" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          }
        }
      }

      # Default max is 1000, create list of 1001 items
      large_array = Enum.map(1..1001, &to_string/1)
      args = %{"items" => large_array}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "exceeds max length"
    end
  end

  describe "nested object handling" do
    test "sanitizes nested objects" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "user" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"},
              "age" => %{"type" => "integer"}
            }
          }
        }
      }

      args = %{"user" => %{"name" => 123, "age" => "25"}}

      assert {:ok, %{"user" => %{"name" => "123", "age" => 25}}} =
               ArgumentSanitizer.sanitize(args, schema)
    end

    test "returns error when nesting exceeds max depth" do
      # Create deeply nested structure
      deep_nested =
        Enum.reduce(1..15, %{"value" => "test"}, fn _i, acc ->
          %{"nested" => acc}
        end)

      schema = %{"type" => "object"}

      assert {:error, msg} = ArgumentSanitizer.sanitize(deep_nested, schema)
      assert msg =~ "exceeds maximum depth"
    end
  end

  describe "string length limits" do
    test "returns error when string exceeds max length" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "content" => %{"type" => "string"}
        }
      }

      # Default max is 100_000 bytes
      large_string = String.duplicate("x", 100_001)
      args = %{"content" => large_string}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "exceeds max length"
    end

    test "passes strings under max length" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "content" => %{"type" => "string"}
        }
      }

      normal_string = String.duplicate("x", 1000)
      args = %{"content" => normal_string}

      assert {:ok, _sanitized} = ArgumentSanitizer.sanitize(args, schema)
    end
  end

  describe "nullable handling" do
    test "allows null when nullable is true" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "optional" => %{"type" => "string", "nullable" => true}
        }
      }

      args = %{"optional" => nil}

      assert {:ok, %{"optional" => nil}} = ArgumentSanitizer.sanitize(args, schema)
    end

    test "uses default value when value is nil and not nullable" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "count" => %{"type" => "integer", "default" => 0}
        }
      }

      args = %{"count" => nil}

      assert {:ok, %{"count" => 0}} = ArgumentSanitizer.sanitize(args, schema)
    end
  end

  describe "validate_required/2" do
    test "returns :ok when all required fields present" do
      schema = %{"required" => ["a", "b"]}
      args = %{"a" => 1, "b" => 2}
      assert :ok = ArgumentSanitizer.validate_required(args, schema)
    end

    test "returns error when required fields missing" do
      schema = %{"required" => ["a", "b"]}
      args = %{"a" => 1}

      assert {:error, "Missing required fields: b"} =
               ArgumentSanitizer.validate_required(args, schema)
    end

    test "returns :ok when no required fields specified" do
      schema = %{}
      args = %{"a" => 1}
      assert :ok = ArgumentSanitizer.validate_required(args, schema)
    end
  end

  describe "edge cases" do
    test "handles non-array value when expecting array" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "items" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          }
        }
      }

      args = %{"items" => "not an array"}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "Expected array"
    end

    test "handles atom values" do
      schema = %{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "string"}}
      }

      args = %{"data" => :some_atom}

      assert {:ok, %{"data" => "some_atom"}} = ArgumentSanitizer.sanitize(args, schema)
    end

    test "handles error in nested property sanitization" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "nested" => %{
            "type" => "object",
            "properties" => %{
              "count" => %{"type" => "integer"}
            }
          }
        }
      }

      args = %{"nested" => %{"count" => "not a number xyz"}}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "Cannot convert"
    end

    test "sanitizes array items and propagates errors" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "numbers" => %{
            "type" => "array",
            "items" => %{"type" => "integer"}
          }
        }
      }

      args = %{"numbers" => [1, 2, "not a number abc"]}

      assert {:error, msg} = ArgumentSanitizer.sanitize(args, schema)
      assert msg =~ "Cannot convert"
    end

    test "handles deeply nested arrays" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "matrix" => %{
            "type" => "array",
            "items" => %{
              "type" => "array",
              "items" => %{"type" => "integer"}
            }
          }
        }
      }

      args = %{"matrix" => [[1, 2], [3, 4]]}

      assert {:ok, %{"matrix" => [[1, 2], [3, 4]]}} =
               ArgumentSanitizer.sanitize(args, schema)
    end
  end
end
