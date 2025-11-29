ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Chatbot.Repo, :manual)

# Define Mox mocks
Mox.defmock(Chatbot.LMStudioMock, for: Chatbot.LMStudioBehaviour)
Mox.defmock(Chatbot.OllamaMock, for: Chatbot.OllamaBehaviour)
