# ex_check configuration for running all quality checks
# See: https://github.com/karolsluszniak/ex_check

[
  ## curated checks - these are run by default in the suggested order

  # Security audit (fast, critical)
  tools: [
    {:hex_audit, command: "mix hex.audit", detect: [{:file, "mix.lock"}]},

    # Compiler (will catch basic errors and warnings)
    {:compiler,
     command: "mix compile --warning-as-errors --all-warnings", detect: [{:file, "mix.exs"}]},

    # Code formatter (fast, deterministic)
    {:formatter, command: "mix format --check-formatted", detect: [{:file, ".formatter.exs"}]},

    # Static code analysis with Credo
    {:credo, command: "mix credo --strict", detect: [{:package, :credo}]},

    # Security-focused static analysis with Sobelow
    {:sobelow, command: "mix sobelow --config", detect: [{:package, :sobelow}]},

    # Type checking with Dialyzer (slower, run in CI primarily)
    {:dialyzer,
     command: "mix dialyzer", detect: [{:package, :dialyxir}], env: %{"MIX_ENV" => "dev"}},

    # Test suite with coverage
    {:ex_unit_with_coverage,
     command: "mix coveralls --min-coverage 80",
     detect: [{:package, :excoveralls}],
     env: %{"MIX_ENV" => "test"}},

    # Unused dependency detection
    {:mix_audit, command: "mix deps.audit", detect: [{:package, :mix_audit}]},

    # Cleanup - unlock unused dependencies
    {:deps_unlock,
     command: "mix deps.unlock --unused --check-unused", detect: [{:file, "mix.lock"}]}
  ],

  ## retry configuration
  retry: [
    {:hex_audit, false},
    {:compiler, false},
    {:formatter, false},
    {:credo, false},
    {:sobelow, false},
    {:dialyzer, false},
    {:ex_unit_with_coverage, false},
    {:mix_audit, false},
    {:deps_unlock, false}
  ],

  ## skipped tools (these can be run manually or in specific contexts)
  skipped: []
]
