defmodule ChatbotWeb.WellKnownController do
  @moduledoc """
  Handles .well-known requests (Chrome DevTools, etc.).

  Returns 404 with empty JSON to silence NoRouteError log noise
  from browser DevTools requesting configuration endpoints.
  """
  use ChatbotWeb, :controller

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{})
  end
end
