defmodule DependencySources do
  @moduledoc false

  # Settled common dependency-source helper.
  #
  # This file is the single reconciled implementation shared by every repository
  # that vendors `build_support/dependency_sources.exs`. It absorbs the useful
  # hardening that had drifted into separate copies:
  #
  #   * absolute `:path` normalization, so a resolved sibling checkout does not
  #     depend on the working directory Mix happens to run from;
  #   * literal-only parsing of the config and local-override files, so neither
  #     can execute arbitrary code during dependency resolution;
  #   * bounded, static name conversion, so no dependency name, source name, or
  #     GitHub option key can create a new atom from file content.
  #
  # It additionally provides:
  #
  #   H1 `publish_preflight/2` - fail-closed check that each committed `hex:`
  #      constraint admits the version in the sibling checkout that was actually
  #      developed against, naming the exact bump required, and (with
  #      `check_registry?: true`) that a package by that name exists on Hex at
  #      all.
  #   H2 `sources/2` / `format_sources/1` / `path_notice/1` and the
  #      `mix deps.sources` task, plus a one-line notice when any dependency
  #      resolves to a local path.
  #   H3 exact `System.argv/0` task-token publish detection. Publish mode is
  #      Hex-only, takes precedence over local overrides, and rejects an
  #      override that requests a non-Hex source. No OS environment variable
  #      selects a dependency source.
  #   H4 `release_dag/0` / `release_order/0` - the machine-readable release
  #      order that H1 reads.

  @helper_version 3

  @source_keys [:path, :github, :hex]
  @source_by_name Map.new(@source_keys, &{Atom.to_string(&1), &1})
  @github_option_keys [:branch, :ref, :tag, :subdir]
  @github_option_by_name Map.new(@github_option_keys, &{Atom.to_string(&1), &1})

  @default_order [:path, :github, :hex]
  @default_publish_order [:hex]

  # H3: the exact mutating package tasks. Read-only tasks such as `hex.info`
  # and `hex.outdated` are deliberately absent - they must resolve exactly the
  # way ordinary development does.
  @publish_tasks ["hex.publish", "hex.build", "deps.publish_preflight"]

  # H2: tasks whose standard output is consumed by other tooling. They never
  # receive the local-path notice.
  @quiet_tasks [
    "run",
    "eval",
    "cmd",
    "app.start",
    "app.config",
    "escript.build",
    "deps.sources",
    "deps.publish_preflight"
  ]

  # H4: the release order for the packages published as one train. An edge
  # `package => [prerequisite]` means the prerequisite must be published first,
  # and its `hex:` constraint bumped in the dependent before the dependent
  # publishes. Packages absent from this map are independent.
  #
  # The Execution Plane components are in this graph because they are a real
  # ordering constraint, not background detail: `cli_subprocess_core` declares
  # all three, and `execution_plane_process` / `execution_plane_jsonrpc` are
  # built to publish (both carry full Hex `package/0` metadata) but are not on
  # the registry yet. Publishing `cli_subprocess_core` before them produces a
  # package whose requirements cannot resolve, which is exactly the class of
  # failure H1's registry check now refuses.
  @release_dag %{
    execution_plane: [],
    execution_plane_process: [:execution_plane],
    execution_plane_jsonrpc: [:execution_plane],
    cli_subprocess_core: [
      :execution_plane,
      :execution_plane_jsonrpc,
      :execution_plane_process
    ],
    codex_sdk: [:cli_subprocess_core],
    claude_agent_sdk: [:cli_subprocess_core],
    cursor_cli_sdk: [:cli_subprocess_core],
    agent_session_manager: [:cli_subprocess_core, :cursor_cli_sdk],
    gemini_ex: [],
    inference: []
  }

  def helper_version, do: @helper_version

  def release_dag, do: @release_dag

  def release_prerequisites(package) when is_atom(package),
    do: Map.get(@release_dag, package, [])

  def release_order do
    @release_dag
    |> Map.keys()
    |> Enum.sort()
    |> topological_order([])
  end

  def config!(repo_root \\ Path.dirname(__DIR__)) do
    repo_root
    |> Path.expand()
    |> Path.join("build_support/dependency_sources.config.exs")
    |> load_config!()
  end

  def deps(repo_root \\ Path.dirname(__DIR__), opts \\ []) do
    repo_root = Path.expand(repo_root)
    selections = selections(repo_root, opts)

    if Keyword.get(opts, :notify?, true) do
      notify_path_sources(repo_root, selections)
    end

    Enum.map(selections, fn {app, dep_config, override, source} ->
      dep_tuple(app, dep_config, source, repo_root, override, [])
    end)
  end

  def dep(app, repo_root \\ Path.dirname(__DIR__), extra_opts \\ []) do
    repo_root = Path.expand(repo_root)
    config = config!(repo_root)
    app_lookup = app_lookup(config)
    overrides = load_local_overrides(repo_root)
    app = normalize_app!(app, app_lookup)
    dep_config = dep_config_for!(app, config, app_lookup)
    override = local_override(app, overrides)
    source = selected_source!(app, dep_config, override, publish_mode?(), repo_root)

    notify_path_sources(repo_root, selections(repo_root, []))

    dep_tuple(app, dep_config, source, repo_root, override, extra_opts)
  end

  # H2 ---------------------------------------------------------------------

  def sources(repo_root \\ Path.dirname(__DIR__), opts \\ []) do
    repo_root = Path.expand(repo_root)

    repo_root
    |> selections(opts)
    |> Enum.map(fn {app, dep_config, override, source} ->
      source_entry(app, dep_config, override, source, repo_root)
    end)
    |> Enum.sort_by(& &1.app)
  end

  def format_sources([]), do: "dependency sources: (no managed dependencies)"

  def format_sources(report) when is_list(report) do
    lines =
      Enum.map(report, fn entry ->
        "  #{entry.app} -> #{entry.source} (#{entry.location}) -> #{entry.version || "unknown"}"
      end)

    Enum.join(["dependency sources:" | lines], "\n")
  end

  def path_notice(report) when is_list(report) do
    case Enum.filter(report, &(&1.source == :path)) do
      [] ->
        nil

      entries ->
        apps = entries |> Enum.map(&to_string(&1.app)) |> Enum.join(", ")
        "[dependency_sources] local path source in use for: #{apps}"
    end
  end

  # H1 ---------------------------------------------------------------------

  def publish_preflight(repo_root \\ Path.dirname(__DIR__), opts \\ []) do
    repo_root = Path.expand(repo_root)
    config = config!(repo_root)
    dependencies = normalized_deps(config)

    package =
      case Keyword.fetch(opts, :package) do
        {:ok, package} -> package
        :error -> current_package(repo_root)
      end

    entries =
      dependencies
      |> Enum.map(fn {app, dep_config} -> preflight_entry(app, dep_config, repo_root) end)
      |> check_registry(Keyword.get(opts, :check_registry?, false))
      |> Enum.sort_by(& &1.app)

    blockers =
      (Enum.filter(entries, &(&1.status == :blocked)) ++
         missing_release_prerequisites(package, dependencies))
      |> Enum.sort_by(& &1.app)

    case blockers do
      [] -> {:ok, entries}
      _ -> {:error, blockers}
    end
  end

  def publish_preflight!(repo_root \\ Path.dirname(__DIR__), opts \\ []) do
    case publish_preflight(repo_root, opts) do
      {:ok, entries} -> entries
      {:error, blockers} -> raise ArgumentError, format_blockers(blockers)
    end
  end

  def format_blockers(blockers) when is_list(blockers) do
    lines = Enum.map(blockers, &("  " <> format_blocker(&1)))
    Enum.join(["publish preflight refused:" | lines], "\n")
  end

  defp format_blocker(%{reason: :hex_constraint_stale} = blocker) do
    "#{blocker.app}: committed hex constraint #{inspect(blocker.hex)} does not admit " <>
      "sibling version #{blocker.sibling_version}; bump it to #{inspect(blocker.required)}"
  end

  defp format_blocker(%{reason: :missing_hex_constraint} = blocker) do
    "#{blocker.app}: no committed hex constraint; publishing requires one " <>
      "(#{inspect(blocker.required)} admits the sibling version)"
  end

  defp format_blocker(%{reason: :invalid_hex_constraint} = blocker) do
    "#{blocker.app}: committed hex constraint #{inspect(blocker.hex)} is not a valid requirement"
  end

  defp format_blocker(%{reason: :unreadable_sibling_version} = blocker) do
    "#{blocker.app}: sibling checkout #{blocker.sibling_path} has no readable mix.exs version"
  end

  defp format_blocker(%{reason: :hex_package_missing} = blocker) do
    "#{blocker.app}: no package with this name exists on the Hex registry, so a " <>
      "published package requiring #{inspect(blocker.hex)} could never resolve"
  end

  defp format_blocker(%{reason: :missing_release_prerequisite} = blocker) do
    "#{blocker.app}: release prerequisite of #{blocker.package} is absent from " <>
      "build_support/dependency_sources.config.exs"
  end

  defp preflight_entry(app, dep_config, repo_root) do
    hex = fetch(dep_config, :hex)
    sibling_path = sibling_path(dep_config, repo_root)

    case sibling_version(sibling_path) do
      :absent -> unverified_entry(app, hex, sibling_path)
      {:error, _reason} -> blocker(app, :unreadable_sibling_version, hex, nil, sibling_path, nil)
      {:ok, version} -> compared_entry(app, hex, version, sibling_path)
    end
  end

  defp compared_entry(app, nil, version, sibling_path) do
    blocker(app, :missing_hex_constraint, nil, version, sibling_path, required(version))
  end

  defp compared_entry(app, hex, version, sibling_path) do
    case requirement_admits?(hex, version) do
      :ok ->
        %{
          app: app,
          status: :ok,
          hex: hex,
          sibling_version: version,
          sibling_path: sibling_path
        }

      :stale ->
        blocker(app, :hex_constraint_stale, hex, version, sibling_path, required(version))

      :invalid ->
        blocker(app, :invalid_hex_constraint, hex, version, sibling_path, required(version))
    end
  end

  defp unverified_entry(app, hex, sibling_path) do
    %{app: app, status: :unverified, hex: hex, sibling_version: nil, sibling_path: sibling_path}
  end

  defp blocker(app, reason, hex, version, sibling_path, required) do
    %{
      app: app,
      status: :blocked,
      reason: reason,
      hex: hex,
      sibling_version: version,
      sibling_path: sibling_path,
      required: required
    }
  end

  defp requirement_admits?(requirement, version) do
    if Version.match?(version, requirement), do: :ok, else: :stale
  rescue
    Version.InvalidRequirementError -> :invalid
    Version.InvalidVersionError -> :invalid
  end

  defp required(version) do
    parsed = Version.parse!(version)
    "~> #{parsed.major}.#{parsed.minor}.0"
  end

  # A committed `hex:` constraint that admits the sibling version is still
  # unpublishable if no such package exists. That is not hypothetical: the
  # Execution Plane split named component packages in every consumer manifest
  # months before either was pushed to the registry, and nothing anywhere
  # noticed until a publish would have failed. Checking the constraint alone
  # was the gap.
  #
  # Off by default so ordinary resolution never touches the network; the
  # `deps.publish_preflight` task turns it on. A registry that cannot be
  # reached is recorded as unverified rather than reported as missing — an
  # offline machine must not manufacture a blocker.
  defp check_registry(entries, false), do: entries

  defp check_registry(entries, true), do: Enum.map(entries, &check_registry_entry/1)

  defp check_registry_entry(%{hex: nil} = entry), do: entry

  defp check_registry_entry(entry) do
    case hex_package_state(entry.app) do
      :published ->
        entry

      :missing ->
        entry
        |> Map.put(:status, :blocked)
        |> Map.put(:reason, :hex_package_missing)
        |> Map.put_new(:required, nil)

      {:unverified, reason} ->
        Map.put(entry, :registry, {:unverified, reason})
    end
  end

  defp hex_package_state(app) do
    case System.cmd("mix", ["hex.info", Atom.to_string(app)], stderr_to_stdout: true) do
      {output, _status} ->
        if String.contains?(output, "No package with name") do
          :missing
        else
          :published
        end
    end
  rescue
    error -> {:unverified, error}
  catch
    :exit, reason -> {:unverified, reason}
  end

  defp missing_release_prerequisites(nil, _dependencies), do: []

  defp missing_release_prerequisites(package, dependencies) do
    declared = Map.new(dependencies) |> Map.keys()

    package
    |> release_prerequisites()
    |> Enum.reject(&(&1 in declared))
    |> Enum.map(fn app ->
      %{
        app: app,
        status: :blocked,
        reason: :missing_release_prerequisite,
        package: package,
        hex: nil,
        sibling_version: nil,
        sibling_path: nil,
        required: nil
      }
    end)
  end

  defp current_package(repo_root) do
    packages = Map.keys(@release_dag)
    app = mix_project_app()

    if app in packages do
      app
    else
      Enum.find(packages, &(Atom.to_string(&1) == Path.basename(repo_root)))
    end
  end

  defp mix_project_app do
    if Code.ensure_loaded?(Mix.Project) and Mix.Project.get() do
      Mix.Project.config()[:app]
    end
  end

  defp topological_order([], placed), do: Enum.reverse(placed)

  defp topological_order(pending, placed) do
    {ready, blocked} =
      Enum.split_with(pending, fn package ->
        Enum.all?(release_prerequisites(package), &(&1 in placed))
      end)

    case ready do
      [] -> raise ArgumentError, "release DAG has a cycle among #{inspect(pending)}"
      _ -> topological_order(blocked, Enum.reverse(ready) ++ placed)
    end
  end

  # Resolution -------------------------------------------------------------

  defp selections(repo_root, opts) do
    config = config!(repo_root)
    overrides = load_local_overrides(repo_root)
    publish? = Keyword.get(opts, :publish?, publish_mode?())

    config
    |> normalized_deps()
    |> Enum.map(fn {app, dep_config} ->
      override = local_override(app, overrides)
      source = selected_source!(app, dep_config, override, publish?, repo_root)
      {app, dep_config, override, source}
    end)
  end

  defp notify_path_sources(repo_root, selections) do
    key = {__MODULE__, :path_notice, repo_root}

    if not quiet_task?() and :persistent_term.get(key, nil) == nil do
      :persistent_term.put(key, true)
      emit_path_notice(selections)
    end

    :ok
  end

  # Tasks whose standard output is the product itself never carry the notice,
  # so nothing that reads `mix` output has an extra line injected into it.
  defp quiet_task? do
    System.argv()
    |> task_tokens()
    |> Enum.any?(&(&1 in @quiet_tasks))
  end

  defp emit_path_notice(selections) do
    report =
      Enum.map(selections, fn {app, _dep_config, _override, source} ->
        %{app: app, source: source}
      end)

    case path_notice(report) do
      nil -> :ok
      message -> Mix.shell().info(message)
    end
  end

  defp source_entry(app, dep_config, override, source, repo_root) do
    %{
      app: app,
      source: source,
      location: source_location(dep_config, override, source, repo_root),
      version: source_version(dep_config, override, source, repo_root)
    }
  end

  defp source_location(dep_config, override, :path, repo_root),
    do: configured_path(dep_config, override, repo_root) || "?"

  defp source_location(dep_config, override, :github, _repo_root) do
    github = github_config(dep_config, override)
    fetch(github, :repo) || "?"
  end

  defp source_location(_dep_config, _override, :hex, _repo_root), do: "hex"

  defp source_version(dep_config, override, :path, repo_root) do
    path = configured_path(dep_config, override, repo_root)

    case path && sibling_version(Path.expand(path, repo_root)) do
      {:ok, version} -> version
      _other -> nil
    end
  end

  defp source_version(dep_config, override, :github, _repo_root) do
    github = github_config(dep_config, override)

    Enum.find_value([:ref, :tag, :branch], fn key ->
      case fetch(github, key) do
        nil -> nil
        value -> "#{key} #{value}"
      end
    end)
  end

  defp source_version(dep_config, override, :hex, _repo_root),
    do: fetch(override, :hex) || fetch(dep_config, :hex)

  defp configured_path(dep_config, override, repo_root) do
    case fetch(override, :path) || fetch(dep_config, :path) do
      nil -> nil
      path when is_binary(path) -> path
      paths when is_list(paths) -> Enum.find(paths, &File.exists?(Path.expand(&1, repo_root)))
      _other -> nil
    end
  end

  defp github_config(dep_config, override) do
    dep_config
    |> fetch(:github)
    |> Kernel.||(%{})
    |> Map.new()
    |> Map.merge(Map.drop(override, [:source, "source"]))
  end

  defp sibling_path(dep_config, repo_root) do
    case configured_path(dep_config, %{}, repo_root) do
      nil -> nil
      path -> Path.expand(path, repo_root)
    end
  end

  defp sibling_version(nil), do: :absent

  defp sibling_version(dir) do
    path = Path.join(dir, "mix.exs")

    if File.regular?(path) do
      read_mix_version(path)
    else
      :absent
    end
  end

  defp read_mix_version(path) do
    quoted = path |> File.read!() |> Code.string_to_quoted!(file: path)
    attributes = module_attributes(quoted)

    case find_version(quoted, attributes) do
      nil -> {:error, :version_not_found}
      version -> {:ok, version}
    end
  rescue
    _error -> {:error, :unparsable_mix_exs}
  end

  defp module_attributes(quoted) do
    {_quoted, attributes} =
      Macro.prewalk(quoted, %{}, fn
        {:@, _meta, [{name, _name_meta, [value]}]} = node, acc when is_atom(name) ->
          if is_binary(value), do: {node, Map.put_new(acc, name, value)}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    attributes
  end

  defp find_version(quoted, attributes) do
    {_quoted, version} =
      Macro.prewalk(quoted, nil, fn
        {:version, value} = node, nil -> {node, version_literal(value, attributes)}
        node, acc -> {node, acc}
      end)

    version
  end

  defp version_literal(value, _attributes) when is_binary(value), do: value

  defp version_literal({:@, _meta, [{name, _name_meta, nil}]}, attributes) when is_atom(name),
    do: Map.get(attributes, name)

  defp version_literal(_value, _attributes), do: nil

  # H3 ---------------------------------------------------------------------

  def publish_mode?, do: publish_mode?(System.argv())

  def publish_mode?(argv) when is_list(argv) do
    argv
    |> task_tokens()
    |> Enum.any?(&(&1 in @publish_tasks))
  end

  defp task_tokens(argv) do
    argv
    |> Enum.flat_map(&split_task_separators/1)
    |> collect_task_tokens(true, [])
    |> Enum.reverse()
  end

  defp split_task_separators(argument) do
    case String.split(argument, ",") do
      [single] -> [single]
      parts -> parts |> Enum.intersperse(",") |> Enum.reject(&(&1 == ""))
    end
  end

  defp collect_task_tokens([], _expect_task?, acc), do: acc

  defp collect_task_tokens([token | rest], _expect_task?, acc) when token in [",", "+"],
    do: collect_task_tokens(rest, true, acc)

  defp collect_task_tokens(["do" | rest], true, acc), do: collect_task_tokens(rest, true, acc)

  defp collect_task_tokens(["" | rest], true, acc), do: collect_task_tokens(rest, true, acc)

  defp collect_task_tokens([token | rest], true, acc),
    do: collect_task_tokens(rest, false, [token | acc])

  defp collect_task_tokens([_token | rest], false, acc),
    do: collect_task_tokens(rest, false, acc)

  # Config loading ---------------------------------------------------------

  defp load_config!(path) do
    config =
      path
      |> File.read!()
      |> Code.string_to_quoted!(file: path)
      |> config_term!(Path.dirname(path))

    unless is_map(config) or Keyword.keyword?(config) do
      raise ArgumentError, "dependency source config must be a literal map or keyword list"
    end

    config
  end

  defp load_local_overrides(repo_root) do
    path = Path.join(repo_root, ".dependency_sources.local.exs")

    if File.regular?(path) do
      overrides =
        path
        |> File.read!()
        |> Code.string_to_quoted!(file: path)
        |> literal_term!()

      Map.new(overrides[:deps] || overrides["deps"] || %{})
    else
      %{}
    end
  end

  defp deps_config(config) do
    deps = config[:deps] || config["deps"] || config
    Map.new(deps)
  end

  defp normalized_deps(config) do
    app_lookup = app_lookup(config)

    config
    |> deps_config()
    |> Enum.map(fn {app, dep_config} ->
      {normalize_app!(app, app_lookup), normalize_dep_config!(dep_config)}
    end)
    |> Enum.sort_by(fn {app, _dep_config} -> app end)
  end

  defp dep_config_for!(app, config, app_lookup) do
    deps =
      config
      |> deps_config()
      |> Map.new(fn {configured_app, dep_config} ->
        {normalize_app!(configured_app, app_lookup), normalize_dep_config!(dep_config)}
      end)

    case Map.fetch(deps, app) do
      {:ok, dep_config} -> dep_config
      :error -> raise ArgumentError, "dependency source config is missing #{app}"
    end
  end

  defp app_lookup(config) do
    config
    |> deps_config()
    |> Map.keys()
    |> Map.new(fn
      app when is_atom(app) -> {Atom.to_string(app), app}
      app when is_binary(app) -> {app, app}
    end)
  end

  defp normalize_app!(app, _app_lookup) when is_atom(app), do: app

  defp normalize_app!(app, app_lookup) when is_binary(app) do
    case Map.fetch(app_lookup, app) do
      {:ok, normalized} -> normalized
      :error -> raise ArgumentError, "dependency source config is missing #{app}"
    end
  end

  defp normalize_dep_config!(config) when is_map(config), do: config
  defp normalize_dep_config!(config) when is_list(config), do: Map.new(config)

  defp local_override(app, overrides),
    do: normalize_dep_config!(overrides[app] || overrides[Atom.to_string(app)] || %{})

  defp fetch(config, key) when is_map(config), do: config[key] || config[Atom.to_string(key)]
  defp fetch(_config, _key), do: nil

  # Source selection -------------------------------------------------------

  defp selected_source!(app, config, override, publish?, repo_root) do
    override_source = fetch(override, :source)

    cond do
      publish? ->
        assert_publishable_override!(app, override_source)
        source_from_order!(app, config, publish_order(config), repo_root)

      override_source ->
        normalize_source!(override_source)

      true ->
        source_from_order!(app, config, default_order(config), repo_root)
    end
  end

  defp assert_publishable_override!(_app, nil), do: :ok

  defp assert_publishable_override!(app, source) do
    case normalize_source!(source) do
      :hex ->
        :ok

      other ->
        raise ArgumentError,
              "publish mode resolves Hex sources only; the local override for " <>
                "#{app} requests #{inspect(other)}"
    end
  end

  defp publish_order(config), do: fetch(config, :publish_order) || @default_publish_order

  defp default_order(config), do: fetch(config, :default_order) || @default_order

  defp source_from_order!(app, config, order, repo_root) do
    order
    |> Enum.map(&normalize_source!/1)
    |> Enum.find(fn
      :path -> configured_path_available?(config, repo_root)
      source -> configured?(config, source)
    end)
    |> case do
      nil -> raise ArgumentError, "no dependency source is available for #{app}"
      source -> source
    end
  end

  defp configured_path_available?(config, repo_root) do
    case fetch(config, :path) do
      nil ->
        false

      path when is_binary(path) ->
        usable_sibling_path?(path, repo_root)

      paths when is_list(paths) ->
        Enum.any?(paths, &usable_sibling_path?(&1, repo_root))

      _other ->
        false
    end
  end

  # A configured `:path` candidate only counts as a usable sibling
  # checkout when (1) it exists on disk and (2) it does not resolve to a
  # Mix-managed `deps/` directory.
  #
  # Without (2), running `mix deps.get` from a fresh clone could
  # materialize multiple sibling deps under the parent project's
  # `deps/`, and this helper -- invoked from within one of those
  # child deps with `repo_root = <parent>/deps/<child>` -- would then
  # mistake another Mix-fetched dep for a developer sibling checkout
  # and pick `:path`. That produces a divergent source vs. however a
  # peer dep already declared the same app, and Mix refuses to
  # resolve with the "overriding a child dependency" error.
  defp usable_sibling_path?(path, repo_root) do
    abs = Path.expand(path, repo_root)
    File.exists?(abs) and not under_mix_deps_dir?(repo_root, abs)
  end

  # When `repo_root` itself sits under a path component named `deps`,
  # `mix_deps_ancestor/1` returns the absolute path to that ancestor
  # (the parent project's `deps/` directory). A candidate that resolves
  # to anything under that same ancestor is therefore another
  # Mix-fetched sibling, not a developer workspace checkout.
  defp under_mix_deps_dir?(repo_root, abs) do
    case mix_deps_ancestor(repo_root) do
      nil -> false
      deps_dir -> String.starts_with?(abs <> "/", deps_dir <> "/")
    end
  end

  defp mix_deps_ancestor(repo_root) do
    segments = repo_root |> Path.expand() |> Path.split()

    segments
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.find(fn {seg, _idx} -> seg == "deps" end)
    |> case do
      nil ->
        nil

      {"deps", reverse_index} ->
        forward_index = length(segments) - reverse_index
        segments |> Enum.take(forward_index) |> Path.join()
    end
  end

  defp configured?(config, source), do: not is_nil(fetch(config, source))

  defp dep_tuple(app, config, :path, repo_root, override, extra_opts) do
    path = configured_path(config, override, repo_root)

    {app,
     Keyword.merge([path: Path.expand(path, repo_root)], dep_options(config, extra_opts))}
  end

  defp dep_tuple(app, config, :github, _repo_root, override, extra_opts) do
    github = github_config(config, override)
    repo = fetch(github, :repo)

    opts =
      github
      |> Enum.flat_map(fn
        {key, _value} when key in [:repo, "repo"] ->
          []

        {key, value} ->
          option_key = normalize_option_key(key)

          if option_key in @github_option_keys do
            [{option_key, value}]
          else
            []
          end
      end)

    {app, Keyword.merge([github: repo], Keyword.merge(opts, dep_options(config, extra_opts)))}
  end

  defp dep_tuple(app, config, :hex, _repo_root, override, extra_opts) do
    requirement = fetch(override, :hex) || fetch(config, :hex)

    case dep_options(config, extra_opts) do
      [] -> {app, requirement}
      opts -> {app, requirement, opts}
    end
  end

  defp dep_options(config, extra_opts) do
    config
    |> Map.get(:opts, config["opts"] || config[:options] || config["options"] || [])
    |> keyword_options()
    |> Keyword.merge(keyword_options(extra_opts))
  end

  defp keyword_options(opts) when is_list(opts), do: opts
  defp keyword_options(opts) when is_map(opts), do: Map.to_list(opts)
  defp keyword_options(_opts), do: []

  defp normalize_source!(source) when source in @source_keys, do: source

  defp normalize_source!(source) when is_binary(source) do
    case Map.fetch(@source_by_name, source) do
      {:ok, normalized} -> normalized
      :error -> raise ArgumentError, "unknown dependency source #{inspect(source)}"
    end
  end

  defp normalize_source!(source) do
    raise ArgumentError, "unknown dependency source #{inspect(source)}"
  end

  defp normalize_option_key(key) when is_atom(key), do: key

  defp normalize_option_key(key) when is_binary(key) do
    case Map.fetch(@github_option_by_name, key) do
      {:ok, normalized} -> normalized
      :error -> key
    end
  end

  # Literal-only evaluation ------------------------------------------------

  defp config_term!(quoted, config_dir) do
    eval_config_ast!(quoted, %{__DIR__: config_dir})
  end

  defp eval_config_ast!({:__block__, _meta, expressions}, env) do
    {value, _env} =
      Enum.reduce(expressions, {nil, env}, fn expression, {_previous, env} ->
        eval_config_expression!(expression, env)
      end)

    value
  end

  defp eval_config_ast!({:%{}, _meta, pairs}, env) do
    Map.new(pairs, fn {key, value} ->
      {eval_config_ast!(key, env), eval_config_ast!(value, env)}
    end)
  end

  defp eval_config_ast!(values, env) when is_list(values),
    do: Enum.map(values, &eval_config_ast!(&1, env))

  defp eval_config_ast!({:<<>>, _meta, parts}, env) do
    parts
    |> Enum.map(&eval_binary_part!(&1, env))
    |> IO.iodata_to_binary()
  end

  defp eval_config_ast!({:"::", _meta, [expression, {:binary, _binary_meta, nil}]}, env),
    do: eval_config_ast!(expression, env)

  defp eval_config_ast!(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Path]}, :expand]}, _call_meta, args},
         env
       )
       when length(args) in [1, 2] do
    args = Enum.map(args, &eval_config_ast!(&1, env))
    apply(Path, :expand, args)
  end

  defp eval_config_ast!(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Path]}, :join]}, _call_meta, args},
         env
       )
       when length(args) in [1, 2] do
    args = Enum.map(args, &eval_config_ast!(&1, env))
    apply(Path, :join, args)
  end

  defp eval_config_ast!({{:., _meta, [Kernel, :to_string]}, _call_meta, [value]}, env),
    do: to_string(eval_config_ast!(value, env))

  defp eval_config_ast!({{:., _meta, [{name, _name_meta, nil}]}, _call_meta, args}, env)
       when is_atom(name) do
    name
    |> fetch_config_env!(env)
    |> call_config_function!(Enum.map(args, &eval_config_ast!(&1, env)))
  end

  defp eval_config_ast!({:fn, _meta, [{:->, _arrow_meta, [params, body]}]}, env) do
    param_names =
      Enum.map(params, fn
        {name, _param_meta, nil} when is_atom(name) ->
          name

        other ->
          raise ArgumentError,
                "dependency source config contains unsupported function parameter #{inspect(other)}"
      end)

    {:dependency_source_config_function, param_names, body, env}
  end

  defp eval_config_ast!({name, _meta, nil}, env) when is_atom(name),
    do: fetch_config_env!(name, env)

  defp eval_config_ast!({left, right}, env),
    do: {eval_config_ast!(left, env), eval_config_ast!(right, env)}

  defp eval_config_ast!(value, _env)
       when is_atom(value) or is_binary(value) or is_integer(value) or is_float(value) or
              is_boolean(value) or is_nil(value),
       do: value

  defp eval_config_ast!(other, _env) do
    raise ArgumentError,
          "dependency source config contains unsupported expression #{inspect(other)}"
  end

  defp eval_config_expression!({:=, _meta, [{name, _name_meta, nil}, value]}, env)
       when is_atom(name) do
    value = eval_config_ast!(value, env)
    {value, Map.put(env, name, value)}
  end

  defp eval_config_expression!(expression, env), do: {eval_config_ast!(expression, env), env}

  defp eval_binary_part!({:"::", _meta, [expression, {:binary, _binary_meta, nil}]}, env),
    do: eval_config_ast!(expression, env)

  defp eval_binary_part!(part, env), do: eval_config_ast!(part, env)

  defp fetch_config_env!(name, env) do
    case Map.fetch(env, name) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError, "dependency source config references unknown binding #{name}"
    end
  end

  defp call_config_function!(
         {:dependency_source_config_function, param_names, body, captured_env},
         args
       ) do
    if length(param_names) != length(args) do
      raise ArgumentError, "dependency source config calls function with wrong arity"
    end

    function_env =
      param_names
      |> Enum.zip(args)
      |> Map.new()
      |> Map.merge(captured_env, fn _key, arg_value, _captured_value -> arg_value end)

    eval_config_ast!(body, function_env)
  end

  defp call_config_function!(other, _args) do
    raise ArgumentError,
          "dependency source config attempts to call non-config function #{inspect(other)}"
  end

  defp literal_term!(value)
       when is_atom(value) or is_binary(value) or is_integer(value) or is_float(value) or
              is_boolean(value) or is_nil(value),
       do: value

  defp literal_term!({:%{}, _meta, pairs}) do
    Map.new(pairs, fn {key, value} -> {literal_term!(key), literal_term!(value)} end)
  end

  defp literal_term!(values) when is_list(values), do: Enum.map(values, &literal_term!/1)

  defp literal_term!({left, right}), do: {literal_term!(left), literal_term!(right)}

  defp literal_term!(other) do
    raise ArgumentError,
          "dependency source local override contains non-literal expression #{inspect(other)}"
  end
end

unless Code.ensure_loaded?(Mix.Tasks.Deps.Sources) do
  defmodule Mix.Tasks.Deps.Sources do
    @moduledoc false
    @shortdoc "Prints the resolved source of every managed dependency"

    use Mix.Task

    # The common helper and the deliberately namespaced Gemini form are the two
    # settled shapes of this file; whichever one the current project loaded is
    # the one to report against.
    @helper_candidates [DependencySources, Gemini.DependencySources]

    @impl Mix.Task
    def run(_args) do
      helper =
        Enum.find(@helper_candidates, &Code.ensure_loaded?/1) ||
          Mix.raise("no dependency source helper is loaded")

      root = File.cwd!()

      root
      |> helper.sources(notify?: false)
      |> helper.format_sources()
      |> Mix.shell().info()
    end
  end
end

unless Code.ensure_loaded?(Mix.Tasks.Deps.PublishPreflight) do
  defmodule Mix.Tasks.Deps.PublishPreflight do
    @moduledoc false
    @shortdoc "Fails closed when a committed hex constraint is behind its sibling checkout"

    use Mix.Task

    @helper_candidates [DependencySources, Gemini.DependencySources]

    @impl Mix.Task
    def run(_args) do
      helper =
        Enum.find(@helper_candidates, &Code.ensure_loaded?/1) ||
          Mix.raise("no dependency source helper is loaded")

      root = File.cwd!()

      case helper.publish_preflight(root, check_registry?: true) do
        {:ok, entries} ->
          Mix.shell().info("publish preflight: ok (#{length(entries)} managed dependencies)")

          Enum.each(entries, fn entry ->
            Mix.shell().info("  #{entry.app} #{entry.status} #{entry.hex}")
          end)

        {:error, blockers} ->
          Mix.raise(helper.format_blockers(blockers))
      end
    end
  end
end
