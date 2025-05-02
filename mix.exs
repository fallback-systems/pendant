defmodule Pendant.MixProject do
  use Mix.Project

  @app :pendant
  @version "0.1.0"
  @all_targets [:rpi4]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      archives: [nerves_bootstrap: "~> 1.13"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}],
      preferred_cli_target: [run: :host, test: :host]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Pendant.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies for all targets
      {:nerves, "~> 1.10", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},

      # Allow Nerves.Runtime on host to support development, testing and CI.
      # See config/host.exs for usage.
      {:nerves_runtime, "~> 0.13.0"},

      # Dependencies for all targets except :host
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},
      
      # WiFi AP and networking
      {:vintage_net_wifi, "~> 0.12.6", targets: @all_targets},
      {:vintage_net_direct, "~> 0.10.7", targets: @all_targets},
      {:vintage_net_ethernet, "~> 0.11.2", targets: @all_targets},
      
      # Web server for the knowledge base
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_view, "~> 0.18"},
      {:floki, "~> 0.30.0", only: :test},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      
      # Meshtastic communication
      {:circuits_uart, "~> 1.5", targets: @all_targets},
      {:circuits_gpio, "~> 1.1", targets: @all_targets},

      # Storage for knowledge base
      {:ecto_sql, "~> 3.9"},
      {:ecto_sqlite3, "~> 0.10"},
      
      # CRDT implementation
      {:delta_crdt, "~> 0.6.5"},
      
      # Dependencies for specific targets
      # NOTE: It's generally low risk and recommended to follow minor version
      # bumps to Nerves systems. Since these include Linux kernel and Erlang
      # version updates, please review their release notes in case
      # changes to your application are needed.
      {:nerves_system_rpi4, "~> 1.24", runtime: false, targets: :rpi4}
    ]
  end

  def release do
    [
      overwrite: true,
      # Erlang distribution is not started automatically.
      # See https://hexdocs.pm/nerves_pack/readme.html#erlang-distribution
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end
end
