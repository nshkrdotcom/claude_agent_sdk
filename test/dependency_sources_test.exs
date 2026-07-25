defmodule DependencySourcesTest do
  use ExUnit.Case, async: true

  @helper DependencySources

  setup do
    workspace =
      Path.join(System.tmp_dir!(), "dependency_sources_#{:erlang.unique_integer([:positive])}")

    root = Path.join(workspace, "package")
    File.mkdir_p!(Path.join(root, "build_support"))
    on_exit(fn -> File.rm_rf!(workspace) end)

    {:ok, workspace: workspace, root: root}
  end

  describe "H1 publish preflight" do
    test "refuses a stale hex constraint and names the exact bump", %{
      workspace: workspace,
      root: root
    } do
      write_sibling!(workspace, "dep_a", "0.3.0")
      write_config!(root, dep_config("dep_a", ~s("~> 0.2.0")))

      assert {:error, [blocker]} = @helper.publish_preflight(root, package: nil)
      assert blocker.app == :dep_a
      assert blocker.reason == :hex_constraint_stale
      assert blocker.hex == "~> 0.2.0"
      assert blocker.sibling_version == "0.3.0"
      assert blocker.required == "~> 0.3.0"
    end

    test "accepts a constraint that admits the sibling version", %{
      workspace: workspace,
      root: root
    } do
      write_sibling!(workspace, "dep_a", "0.3.1")
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))

      assert {:ok, [entry]} = @helper.publish_preflight(root, package: nil)
      assert entry.app == :dep_a
      assert entry.status == :ok
      assert entry.sibling_version == "0.3.1"
    end

    test "refuses a dependency with no committed hex constraint", %{
      workspace: workspace,
      root: root
    } do
      write_sibling!(workspace, "dep_a", "0.3.0")

      write_config!(root, """
      %{
        deps: %{
          dep_a: %{
            path: "../dep_a",
            default_order: [:path],
            publish_order: [:hex]
          }
        }
      }
      """)

      assert {:error, [blocker]} = @helper.publish_preflight(root, package: nil)
      assert blocker.reason == :missing_hex_constraint
      assert blocker.required == "~> 0.3.0"
    end

    test "refuses a sibling whose version cannot be read", %{workspace: workspace, root: root} do
      dir = Path.join(workspace, "dep_a")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "mix.exs"), "defmodule DepA.MixProject do\nend\n")
      write_config!(root, dep_config("dep_a", ~s("~> 0.2.0")))

      assert {:error, [blocker]} = @helper.publish_preflight(root, package: nil)
      assert blocker.reason == :unreadable_sibling_version
    end

    test "reports an absent sibling as unverified rather than passing it silently", %{root: root} do
      write_config!(root, dep_config("dep_a", ~s("~> 0.2.0")))

      assert {:ok, [entry]} = @helper.publish_preflight(root, package: nil)
      assert entry.status == :unverified
      assert entry.sibling_version == nil
    end

    test "refuses a release-DAG prerequisite missing from the manifest", %{
      workspace: workspace,
      root: root
    } do
      write_sibling!(workspace, "cli_subprocess_core", "0.2.0")
      write_config!(root, dep_config("cli_subprocess_core", ~s("~> 0.2.0")))

      assert {:error, blockers} =
               @helper.publish_preflight(root, package: :agent_session_manager)

      assert [%{app: :cursor_cli_sdk, reason: :missing_release_prerequisite}] = blockers
    end

    test "an empty manifest has nothing to preflight", %{root: root} do
      write_config!(root, "%{deps: %{}}\n")

      assert {:ok, []} = @helper.publish_preflight(root, package: nil)
    end
  end

  describe "H2 source visibility" do
    test "sources/2 reports the selected source and resolved version", %{
      workspace: workspace,
      root: root
    } do
      write_sibling!(workspace, "dep_a", "0.3.0")
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))

      assert [entry] = @helper.sources(root)
      assert entry.app == :dep_a
      assert entry.source == :path
      assert entry.location == "../dep_a"
      assert entry.version == "0.3.0"

      formatted = @helper.format_sources(@helper.sources(root))
      assert formatted =~ "dep_a -> path (../dep_a) -> 0.3.0"
    end

    test "sources/2 reports the hex requirement under publish mode", %{
      workspace: workspace,
      root: root
    } do
      write_sibling!(workspace, "dep_a", "0.3.0")
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))

      assert [entry] = @helper.sources(root, publish?: true)
      assert entry.source == :hex
      assert entry.version == "~> 0.3.0"
    end

    test "format_sources/1 says so when nothing is managed", %{root: root} do
      write_config!(root, "%{deps: %{}}\n")

      assert @helper.format_sources(@helper.sources(root)) =~ "(no managed dependencies)"
    end

    test "path_notice/1 names every dependency resolving to a local checkout", %{
      workspace: workspace,
      root: root
    } do
      write_sibling!(workspace, "dep_a", "0.3.0")
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))

      assert @helper.path_notice(@helper.sources(root)) =~ "dep_a"
      assert @helper.path_notice(@helper.sources(root, publish?: true)) == nil
    end
  end

  describe "H3 publish detection" do
    test "recognizes exact publish task tokens" do
      assert @helper.publish_mode?(["hex.publish", "--yes"])
      assert @helper.publish_mode?(["hex.build"])
      assert @helper.publish_mode?(["deps.publish_preflight"])
      assert @helper.publish_mode?(["do", "deps.get,", "hex.publish"])
      assert @helper.publish_mode?(["do", "deps.get", "+", "hex.publish"])
    end

    test "read-only hex tasks are not publish mode" do
      refute @helper.publish_mode?(["hex.info"])
      refute @helper.publish_mode?(["hex.outdated"])
      refute @helper.publish_mode?([])
      refute @helper.publish_mode?(["compile"])
    end

    test "a task argument that looks like a task is not a task token" do
      refute @helper.publish_mode?(["hex.info", "hex.publish"])
    end

    test "publish mode selects hex ahead of an available sibling path", %{
      workspace: workspace,
      root: root
    } do
      write_sibling!(workspace, "dep_a", "0.3.0")
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))

      assert [{:dep_a, "~> 0.3.0"}] = @helper.deps(root, publish?: true, notify?: false)
    end

    test "publish mode refuses a local override requesting a non-hex source", %{
      workspace: workspace,
      root: root
    } do
      write_sibling!(workspace, "dep_a", "0.3.0")
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))
      write_local_override!(root, "%{deps: %{dep_a: %{source: :path}}}\n")

      assert_raise ArgumentError, ~r/publish mode/, fn ->
        @helper.deps(root, publish?: true, notify?: false)
      end
    end

    test "a local override still wins outside publish mode", %{workspace: workspace, root: root} do
      write_sibling!(workspace, "dep_a", "0.3.0")
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))
      write_local_override!(root, "%{deps: %{dep_a: %{source: :hex, hex: \"~> 9.9.0\"}}}\n")

      assert [{:dep_a, "~> 9.9.0"}] = @helper.deps(root, notify?: false)
    end
  end

  describe "H4 release DAG" do
    test "declares the actual release edges" do
      dag = @helper.release_dag()

      assert dag[:cli_subprocess_core] == []
      assert dag[:codex_sdk] == [:cli_subprocess_core]
      assert dag[:claude_agent_sdk] == [:cli_subprocess_core]
      assert dag[:cursor_cli_sdk] == [:cli_subprocess_core]
      assert dag[:agent_session_manager] == [:cli_subprocess_core, :cursor_cli_sdk]
      assert dag[:gemini_ex] == []
      assert dag[:inference] == []
    end

    test "release_order/0 publishes every prerequisite first" do
      order = @helper.release_order()

      for {package, prerequisites} <- @helper.release_dag(),
          prerequisite <- prerequisites do
        assert index_of(order, prerequisite) < index_of(order, package),
               "#{prerequisite} must publish before #{package}"
      end
    end
  end

  describe "reconciled hardening" do
    test "a path dependency resolves to an absolute path", %{workspace: workspace, root: root} do
      write_sibling!(workspace, "dep_a", "0.3.0")
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))

      assert [{:dep_a, opts}] = @helper.deps(root, notify?: false)
      assert Path.type(opts[:path]) == :absolute
      assert opts[:path] == Path.join(workspace, "dep_a")
    end

    test "a non-literal config expression is refused instead of evaluated", %{root: root} do
      write_config!(root, ~s|%{deps: %{dep_a: %{hex: System.get_env("PATH")}}}\n|)

      assert_raise ArgumentError, ~r/unsupported expression/, fn -> @helper.sources(root) end
    end

    test "a non-literal local override is refused instead of evaluated", %{root: root} do
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))
      write_local_override!(root, ~s|%{deps: %{dep_a: %{hex: System.get_env("PATH")}}}\n|)

      assert_raise ArgumentError, ~r/non-literal/, fn ->
        @helper.deps(root, notify?: false)
      end
    end

    test "an unknown source name is refused without creating an atom", %{root: root} do
      write_config!(root, """
      %{deps: %{dep_a: %{hex: "~> 0.3.0", default_order: ["mystery"]}}}
      """)

      assert_raise ArgumentError, ~r/unknown dependency source/, fn ->
        @helper.deps(root, notify?: false)
      end
    end

    test "an undeclared dependency name is refused", %{root: root} do
      write_config!(root, dep_config("dep_a", ~s("~> 0.3.0")))

      assert_raise ArgumentError, ~r/dep_b/, fn -> @helper.dep("dep_b", root) end
    end

    test "the helper reports its settled version" do
      assert @helper.helper_version() >= 3
    end
  end

  defp index_of(list, element), do: Enum.find_index(list, &(&1 == element))

  defp dep_config(name, hex_source) do
    """
    %{
      deps: %{
        #{name}: %{
          path: "../#{name}",
          github: %{repo: "nshkrdotcom/#{name}", branch: "main"},
          hex: #{hex_source},
          default_order: [:path, :github, :hex],
          publish_order: [:hex]
        }
      }
    }
    """
  end

  defp write_config!(root, source) do
    File.mkdir_p!(Path.join(root, "build_support"))
    File.write!(Path.join(root, "build_support/dependency_sources.config.exs"), source)
  end

  defp write_local_override!(root, source) do
    File.write!(Path.join(root, ".dependency_sources.local.exs"), source)
  end

  defp write_sibling!(workspace, name, version) do
    dir = Path.join(workspace, name)
    File.mkdir_p!(dir)

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      @version "#{version}"

      def project do
        [app: :#{name}, version: @version]
      end
    end
    """)

    dir
  end
end

defmodule DependencySourcesNoticeTest do
  use ExUnit.Case, async: false

  @helper DependencySources

  setup do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "dependency_sources_notice_#{:erlang.unique_integer([:positive])}"
      )

    root = Path.join(workspace, "package")
    File.mkdir_p!(Path.join(root, "build_support"))

    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(shell)
      File.rm_rf!(workspace)
    end)

    {:ok, workspace: workspace, root: root}
  end

  test "deps/2 announces local path resolution exactly once per project", %{
    workspace: workspace,
    root: root
  } do
    dir = Path.join(workspace, "dep_a")
    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "mix.exs"),
      ~s|defmodule A.MixProject do\n  def project, do: [version: "0.3.0"]\nend\n|
    )

    File.write!(Path.join(root, "build_support/dependency_sources.config.exs"), """
    %{
      deps: %{
        dep_a: %{
          path: "../dep_a",
          hex: "~> 0.3.0",
          default_order: [:path, :hex],
          publish_order: [:hex]
        }
      }
    }
    """)

    @helper.deps(root)
    assert_received {:mix_shell, :info, [message]}
    assert message =~ "dep_a"
    assert message =~ "path"

    @helper.deps(root)
    refute_received {:mix_shell, :info, [_]}
  end
end
