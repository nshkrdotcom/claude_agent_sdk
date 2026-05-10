defmodule DependencySources do
  @moduledoc false

  @helper_version 1
  @source_keys [:path, :github, :hex]
  @github_option_keys [:branch, :ref, :tag, :subdir]

  def helper_version, do: @helper_version

  def deps(repo_root \\ Path.dirname(__DIR__), opts \\ []) do
    repo_root = Path.expand(repo_root)
    config = load_config!(Path.join(repo_root, "build_support/dependency_sources.config.exs"))
    overrides = load_local_overrides(repo_root)
    publish? = Keyword.get(opts, :publish?, publish_mode?())

    config
    |> deps_config()
    |> Enum.map(fn {app, dep_config} ->
      app = normalize_app!(app)
      dep_config = normalize_dep_config!(dep_config)
      override = local_override(app, overrides)
      source = selected_source!(app, dep_config, override, publish?, repo_root)
      dep_tuple(app, dep_config, source, repo_root, override, [])
    end)
  end

  def dep(app, repo_root \\ Path.dirname(__DIR__), extra_opts \\ []) do
    repo_root = Path.expand(repo_root)
    config = load_config!(Path.join(repo_root, "build_support/dependency_sources.config.exs"))
    overrides = load_local_overrides(repo_root)
    app = normalize_app!(app)
    dep_config = dep_config_for!(app, config)
    override = local_override(app, overrides)
    source = selected_source!(app, dep_config, override, publish_mode?(), repo_root)

    dep_tuple(app, dep_config, source, repo_root, override, extra_opts)
  end

  defp load_config!(path) do
    {config, _binding} = Code.eval_file(path)

    unless is_map(config) or Keyword.keyword?(config) do
      raise ArgumentError, "dependency source config must evaluate to a map or keyword list"
    end

    config
  end

  defp load_local_overrides(repo_root) do
    path = Path.join(repo_root, ".dependency_sources.local.exs")

    if File.regular?(path) do
      {overrides, _binding} = Code.eval_file(path)
      Map.new(overrides[:deps] || overrides["deps"] || %{})
    else
      %{}
    end
  end

  defp deps_config(config) do
    deps = config[:deps] || config["deps"] || config
    Map.new(deps)
  end

  defp dep_config_for!(app, config) do
    deps =
      config
      |> deps_config()
      |> Map.new(fn {configured_app, dep_config} ->
        {normalize_app!(configured_app), normalize_dep_config!(dep_config)}
      end)

    case Map.fetch(deps, app) do
      {:ok, dep_config} -> dep_config
      :error -> raise ArgumentError, "dependency source config is missing #{app}"
    end
  end

  defp normalize_app!(app) when is_atom(app), do: app
  defp normalize_app!(app) when is_binary(app), do: String.to_atom(app)

  defp normalize_dep_config!(config) when is_map(config), do: config
  defp normalize_dep_config!(config) when is_list(config), do: Map.new(config)

  defp local_override(app, overrides),
    do: normalize_dep_config!(overrides[app] || overrides[Atom.to_string(app)] || %{})

  defp selected_source!(app, config, override, publish?, repo_root) do
    override_source = override[:source] || override["source"]

    cond do
      override_source ->
        normalize_source!(override_source)

      publish? ->
        source_from_order!(
          app,
          config,
          config[:publish_order] || config["publish_order"] || [:hex],
          repo_root
        )

      true ->
        source_from_order!(
          app,
          config,
          config[:default_order] || config["default_order"] || [:path, :github, :hex],
          repo_root
        )
    end
  end

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
    case config[:path] || config["path"] do
      nil ->
        false

      path when is_binary(path) ->
        File.exists?(Path.expand(path, repo_root))

      paths when is_list(paths) ->
        Enum.any?(paths, &File.exists?(Path.expand(&1, repo_root)))

      _other ->
        false
    end
  end

  defp configured?(config, source),
    do: not is_nil(config[source] || config[Atom.to_string(source)])

  defp dep_tuple(app, config, :path, repo_root, override, extra_opts) do
    path = override[:path] || override["path"] || config[:path] || config["path"]

    path =
      if is_list(path), do: Enum.find(path, &File.exists?(Path.expand(&1, repo_root))), else: path

    {app, Keyword.merge([path: path], dep_options(config, extra_opts))}
  end

  defp dep_tuple(app, config, :github, _repo_root, override, extra_opts) do
    github = Map.new(config[:github] || config["github"] || %{})
    github = Map.merge(github, Map.drop(override, [:source, "source"]))
    repo = github[:repo] || github["repo"]

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
    requirement = override[:hex] || override["hex"] || config[:hex] || config["hex"]

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
  defp normalize_source!(source) when is_binary(source), do: String.to_existing_atom(source)

  defp normalize_option_key(key) when is_atom(key), do: key
  defp normalize_option_key(key) when is_binary(key), do: String.to_existing_atom(key)

  defp publish_mode? do
    System.argv()
    |> Enum.join(" ")
    |> String.contains?("hex.")
  end
end
