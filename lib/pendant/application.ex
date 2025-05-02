defmodule Pendant.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Children for all targets
        {Phoenix.PubSub, name: Pendant.PubSub},
        {Pendant.KnowledgeBase.Repo, []},
        {Pendant.Web.Endpoint, []},
        {Pendant.NetworkManager, []},
        {Pendant.Chat.CRDTSupervisor, []},
        {Pendant.RateLimiter, []},
      ] ++ target_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pendant.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  if Mix.target() == :host do
    defp target_children() do
      [
        # Children that only run on the host during development or test.
        # In general, prefer using `config/host.exs` for differences.
      ]
    end
  else
    defp target_children() do
      [
        # Children for all targets except host
        {Pendant.Meshtastic.Handler, []},
        {Pendant.WiFi.AccessPoint, []},
        {Pendant.WiFi.Client, []},
        {Pendant.P2P.Manager, []}
      ]
    end
  end
end
