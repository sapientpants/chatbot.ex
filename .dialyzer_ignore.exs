[
  # Ignore ExUnit-related warnings in test support files
  # These are common false positives when using ExUnit.CaseTemplate
  {"test/support/conn_case.ex", :unknown_function},
  {"test/support/data_case.ex", :unknown_function},

  # Pgvector library doesn't export a t() type for its Ecto type module
  # The Ecto type Pgvector.Ecto.Vector works correctly at runtime
  {"lib/chatbot/memory/user_memory.ex", :unknown_type},
  {"lib/chatbot/memory/search.ex", :unknown_type},
  {"lib/chatbot/chat/attachment_chunk.ex", :unknown_type},
  {"lib/chatbot/rag/chunk_search.ex", :unknown_type},
  {"lib/chatbot/search/search_utils.ex", :unknown_type},

  # RAG modules have @specs with {:error, term()} return types
  # Dialyzer's extra_range means these functions currently always succeed
  # but the error path exists for robustness and future changes
  {"lib/chatbot/rag/chunk_search.ex", :extra_range},
  {"lib/chatbot/rag/query_expander.ex", :extra_range},
  {"lib/chatbot/rag/reranker.ex", :extra_range},
  {"lib/chatbot/rag/reranker.ex", :pattern_match_cov},

  # MCP infrastructure uses fuse (Erlang circuit breaker library)
  # Dialyzer has trouble analyzing Erlang interop calls to :fuse module
  # This causes cascading "unused_fun" and "no_return" warnings
  {"lib/chatbot/mcp/client_registry.ex", :call},
  {"lib/chatbot/mcp/client_registry.ex", :no_return},
  {"lib/chatbot/mcp/client_registry.ex", :invalid_contract},
  {"lib/chatbot/mcp/client_registry.ex", :extra_range},
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
  {"lib/chatbot/mcp/tool_registry.ex", :unused_fun},

  # ArgumentSanitizer handles external input where types are not guaranteed
  # Dialyzer's type narrowing causes false positives for defensive type checking
  {"lib/chatbot/mcp/argument_sanitizer.ex", :guard_fail},
  {"lib/chatbot/mcp/argument_sanitizer.ex", :pattern_match},
  {"lib/chatbot/mcp/argument_sanitizer.ex", :pattern_match_cov},

  # SecurityLog log/3 function handles :info/:warning/:error levels
  # Dialyzer narrows the type based on actual usage but all branches are valid
  {"lib/chatbot/security_log.ex", :pattern_match},

  # TaskRegistry max_concurrent_tasks/0 returns a compile-time constant
  # The @spec is intentionally broader for future configurability
  {"lib/chatbot_web/live/chat/task_registry.ex", :contract_supertype},

  # ConversationAttachment returns compile-time constants for max_file_size and max_attachments
  # The @spec is intentionally broader (pos_integer) for future configurability
  {"lib/chatbot/chat/conversation_attachment.ex", :contract_supertype}
]
