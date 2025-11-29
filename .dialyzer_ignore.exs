[
  # Ignore ExUnit-related warnings in test support files
  # These are common false positives when using ExUnit.CaseTemplate
  {"test/support/conn_case.ex", :unknown_function},
  {"test/support/data_case.ex", :unknown_function},

  # Pgvector library doesn't export a t() type for its Ecto type module
  # The Ecto type Pgvector.Ecto.Vector works correctly at runtime
  {"lib/chatbot/memory/user_memory.ex", :unknown_type},
  {"lib/chatbot/memory/search.ex", :unknown_type}
]
