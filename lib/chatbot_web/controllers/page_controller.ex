defmodule ChatbotWeb.PageController do
  use ChatbotWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
