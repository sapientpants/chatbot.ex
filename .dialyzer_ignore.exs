[
  # Ignore ExUnit-related warnings in test support files
  # These are common false positives when using ExUnit.CaseTemplate
  {"test/support/conn_case.ex", :unknown_function},
  {"test/support/data_case.ex", :unknown_function},
  # Ecto.Multi opaque type warnings - these are false positives due to how
  # Dialyzer handles Ecto's internal types
  {"lib/chatbot/accounts.ex", :call_without_opaque}
]
