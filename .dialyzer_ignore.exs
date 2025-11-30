[
  # Ignore ExUnit-related warnings in test support files
  # These are common false positives when using ExUnit.CaseTemplate
  {"test/support/conn_case.ex", :unknown_function},
  {"test/support/data_case.ex", :unknown_function},

  # Pgvector library doesn't export a t() type for its Ecto type module
  # The Ecto type Pgvector.Ecto.Vector works correctly at runtime
  {"lib/chatbot/memory/user_memory.ex", :unknown_type},
  {"lib/chatbot/memory/search.ex", :unknown_type},

  # MCP infrastructure uses fuse (Erlang circuit breaker library)
  # Dialyzer has trouble analyzing Erlang interop calls to :fuse module
  # This causes cascading "unused_fun" and "no_return" warnings
  {"lib/chatbot/mcp/client_registry.ex", :call},
  {"lib/chatbot/mcp/client_registry.ex", :no_return},
  {"lib/chatbot/mcp/client_registry.ex", :invalid_contract},
  {"lib/chatbot/mcp/client_registry.ex", :unused_fun},

  # MCP tool executor and registry have cascading issues from fuse interop
  {"lib/chatbot/mcp/tool_executor.ex", :call},
  {"lib/chatbot/mcp/tool_executor.ex", :no_return},
  {"lib/chatbot/mcp/tool_executor.ex", :pattern_match},
  {"lib/chatbot/mcp/tool_executor.ex", :pattern_match_cov},
  {"lib/chatbot/mcp/tool_executor.ex", :unused_fun},
  {"lib/chatbot/mcp/tool_registry.ex", :call},
  {"lib/chatbot/mcp/tool_registry.ex", :no_return},
  {"lib/chatbot/mcp/tool_registry.ex", :pattern_match},
  {"lib/chatbot/mcp/tool_registry.ex", :pattern_match_cov},
  {"lib/chatbot/mcp/tool_registry.ex", :extra_range},
  {"lib/chatbot/mcp/tool_registry.ex", :unused_fun}
]
