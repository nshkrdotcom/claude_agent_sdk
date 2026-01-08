defmodule EmailAgent.RulesTest do
  use ExUnit.Case, async: true

  alias EmailAgent.Email
  alias EmailAgent.Rules

  describe "load_rules/1" do
    test "loads rules from JSON file" do
      rules_json = """
      {
        "rules": [
          {
            "name": "Archive old newsletters",
            "condition": {
              "from_contains": "newsletter",
              "older_than_days": 7
            },
            "action": {
              "type": "move",
              "destination": "Archive"
            }
          }
        ]
      }
      """

      File.write!("priv/test_rules.json", rules_json)

      on_exit(fn -> File.rm("priv/test_rules.json") end)

      assert {:ok, rules} = Rules.load_rules("priv/test_rules.json")

      assert length(rules) == 1
      assert hd(rules).name == "Archive old newsletters"
    end

    test "returns empty list for missing file" do
      assert {:ok, []} = Rules.load_rules("priv/nonexistent_rules.json")
    end

    test "returns error for invalid JSON" do
      File.write!("priv/invalid_rules.json", "not valid json")

      on_exit(fn -> File.rm("priv/invalid_rules.json") end)

      assert {:error, _reason} = Rules.load_rules("priv/invalid_rules.json")
    end
  end

  describe "parse_rule/1" do
    test "parses rule with from_contains condition" do
      rule_map = %{
        "name" => "Test Rule",
        "condition" => %{
          "from_contains" => "newsletter"
        },
        "action" => %{
          "type" => "label",
          "label" => "newsletters"
        }
      }

      {:ok, rule} = Rules.parse_rule(rule_map)

      assert rule.name == "Test Rule"
      assert rule.condition.from_contains == "newsletter"
      assert rule.action.type == :label
      assert rule.action.label == "newsletters"
    end

    test "parses rule with subject_contains condition" do
      rule_map = %{
        "name" => "Urgent Emails",
        "condition" => %{
          "subject_contains" => "URGENT"
        },
        "action" => %{
          "type" => "star"
        }
      }

      {:ok, rule} = Rules.parse_rule(rule_map)

      assert rule.condition.subject_contains == "URGENT"
      assert rule.action.type == :star
    end

    test "parses rule with multiple conditions" do
      rule_map = %{
        "name" => "Complex Rule",
        "condition" => %{
          "from_contains" => "boss",
          "subject_contains" => "review",
          "has_attachment" => true
        },
        "action" => %{
          "type" => "label",
          "label" => "priority"
        }
      }

      {:ok, rule} = Rules.parse_rule(rule_map)

      assert rule.condition.from_contains == "boss"
      assert rule.condition.subject_contains == "review"
      assert rule.condition.has_attachment == true
    end

    test "parses move action" do
      rule_map = %{
        "name" => "Archive Rule",
        "condition" => %{},
        "action" => %{
          "type" => "move",
          "destination" => "Archive"
        }
      }

      {:ok, rule} = Rules.parse_rule(rule_map)

      assert rule.action.type == :move
      assert rule.action.destination == "Archive"
    end

    test "parses mark_read action" do
      rule_map = %{
        "name" => "Auto-read Rule",
        "condition" => %{},
        "action" => %{
          "type" => "mark_read"
        }
      }

      {:ok, rule} = Rules.parse_rule(rule_map)

      assert rule.action.type == :mark_read
    end

    test "returns error for missing name" do
      rule_map = %{
        "condition" => %{},
        "action" => %{"type" => "star"}
      }

      assert {:error, :missing_name} = Rules.parse_rule(rule_map)
    end

    test "returns error for missing action" do
      rule_map = %{
        "name" => "Incomplete Rule",
        "condition" => %{}
      }

      assert {:error, :missing_action} = Rules.parse_rule(rule_map)
    end
  end

  describe "matches?/2" do
    test "matches email with from_contains condition" do
      rule = %Rules.Rule{
        name: "Newsletter Rule",
        condition: %Rules.Condition{
          from_contains: "newsletter"
        },
        action: %Rules.Action{type: :label, label: "newsletters"},
        enabled: true
      }

      matching_email = build_email(from: "newsletter@company.com")
      non_matching_email = build_email(from: "john@company.com")

      assert Rules.matches?(rule, matching_email) == true
      assert Rules.matches?(rule, non_matching_email) == false
    end

    test "matches email with subject_contains condition" do
      rule = %Rules.Rule{
        name: "Urgent Rule",
        condition: %Rules.Condition{
          subject_contains: "urgent"
        },
        action: %Rules.Action{type: :star},
        enabled: true
      }

      matching_email = build_email(subject: "URGENT: Please respond")
      non_matching_email = build_email(subject: "Regular email")

      assert Rules.matches?(rule, matching_email) == true
      assert Rules.matches?(rule, non_matching_email) == false
    end

    test "matches email with has_attachment condition" do
      rule = %Rules.Rule{
        name: "Attachment Rule",
        condition: %Rules.Condition{
          has_attachment: true
        },
        action: %Rules.Action{type: :label, label: "attachments"},
        enabled: true
      }

      with_attachment = build_email(attachments: [%{filename: "doc.pdf"}])
      without_attachment = build_email(attachments: [])

      assert Rules.matches?(rule, with_attachment) == true
      assert Rules.matches?(rule, without_attachment) == false
    end

    test "matches email with older_than_days condition" do
      rule = %Rules.Rule{
        name: "Old Email Rule",
        condition: %Rules.Condition{
          older_than_days: 7
        },
        action: %Rules.Action{type: :move, destination: "Archive"},
        enabled: true
      }

      old_date = DateTime.add(DateTime.utc_now(), -10, :day)
      recent_date = DateTime.add(DateTime.utc_now(), -3, :day)

      old_email = build_email(date: old_date)
      recent_email = build_email(date: recent_date)

      assert Rules.matches?(rule, old_email) == true
      assert Rules.matches?(rule, recent_email) == false
    end

    test "all conditions must match (AND logic)" do
      rule = %Rules.Rule{
        name: "Complex Rule",
        condition: %Rules.Condition{
          from_contains: "boss",
          subject_contains: "review"
        },
        action: %Rules.Action{type: :star},
        enabled: true
      }

      both_match = build_email(from: "boss@company.com", subject: "Please review")
      only_from = build_email(from: "boss@company.com", subject: "Hello")
      only_subject = build_email(from: "colleague@company.com", subject: "Review needed")

      assert Rules.matches?(rule, both_match) == true
      assert Rules.matches?(rule, only_from) == false
      assert Rules.matches?(rule, only_subject) == false
    end

    test "disabled rules never match" do
      rule = %Rules.Rule{
        name: "Disabled Rule",
        condition: %Rules.Condition{
          from_contains: "anyone"
        },
        action: %Rules.Action{type: :star},
        enabled: false
      }

      email = build_email(from: "anyone@example.com")

      assert Rules.matches?(rule, email) == false
    end
  end

  describe "apply_rule/3" do
    setup do
      db_path = "priv/test_rules_#{:erlang.unique_integer([:positive])}.db"
      File.rm(db_path)
      {:ok, conn} = EmailAgent.Storage.init_db(database_path: db_path)
      {:ok, pid} = EmailAgent.Storage.start_link(database_path: db_path, name: nil)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        EmailAgent.Storage.close(conn)
        File.rm(db_path)
      end)

      {:ok, storage: pid}
    end

    test "applies label action", %{storage: storage} do
      rule = %Rules.Rule{
        name: "Label Rule",
        condition: %Rules.Condition{},
        action: %Rules.Action{type: :label, label: "important"},
        enabled: true
      }

      email = build_email(labels: ["inbox"])
      # Insert email first
      {:ok, _} = EmailAgent.Storage.insert_email(storage, email)

      {:ok, updated} = Rules.apply_rule(rule, email, storage)

      assert "important" in updated.labels
    end

    test "applies star action", %{storage: storage} do
      rule = %Rules.Rule{
        name: "Star Rule",
        condition: %Rules.Condition{},
        action: %Rules.Action{type: :star},
        enabled: true
      }

      email = build_email(is_starred: false)
      {:ok, _} = EmailAgent.Storage.insert_email(storage, email)

      {:ok, updated} = Rules.apply_rule(rule, email, storage)

      assert updated.is_starred == true
    end

    test "applies mark_read action", %{storage: storage} do
      rule = %Rules.Rule{
        name: "Mark Read Rule",
        condition: %Rules.Condition{},
        action: %Rules.Action{type: :mark_read},
        enabled: true
      }

      email = build_email(is_read: false)
      {:ok, _} = EmailAgent.Storage.insert_email(storage, email)

      {:ok, updated} = Rules.apply_rule(rule, email, storage)

      assert updated.is_read == true
    end

    test "applies move action", %{storage: storage} do
      rule = %Rules.Rule{
        name: "Move Rule",
        condition: %Rules.Condition{},
        action: %Rules.Action{type: :move, destination: "Archive"},
        enabled: true
      }

      email = build_email(labels: ["inbox"])
      {:ok, _} = EmailAgent.Storage.insert_email(storage, email)

      {:ok, updated} = Rules.apply_rule(rule, email, storage)

      assert "Archive" in updated.labels
      refute "inbox" in updated.labels
    end
  end

  describe "process_email/3" do
    setup do
      db_path = "priv/test_rules_proc_#{:erlang.unique_integer([:positive])}.db"
      File.rm(db_path)
      {:ok, conn} = EmailAgent.Storage.init_db(database_path: db_path)
      {:ok, pid} = EmailAgent.Storage.start_link(database_path: db_path, name: nil)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        EmailAgent.Storage.close(conn)
        File.rm(db_path)
      end)

      {:ok, storage: pid}
    end

    test "applies matching rules to email", %{storage: storage} do
      rules = [
        %Rules.Rule{
          name: "Newsletter Rule",
          condition: %Rules.Condition{from_contains: "newsletter"},
          action: %Rules.Action{type: :label, label: "newsletters"},
          enabled: true
        },
        %Rules.Rule{
          name: "Urgent Rule",
          condition: %Rules.Condition{subject_contains: "urgent"},
          action: %Rules.Action{type: :star},
          enabled: true
        }
      ]

      email =
        build_email(
          from: "newsletter@company.com",
          subject: "URGENT: Weekly Newsletter"
        )

      {:ok, _} = EmailAgent.Storage.insert_email(storage, email)

      {:ok, updated, applied_rules} = Rules.process_email(email, rules, storage)

      assert length(applied_rules) == 2
      assert "newsletters" in updated.labels
      assert updated.is_starred == true
    end

    test "skips non-matching rules", %{storage: storage} do
      rules = [
        %Rules.Rule{
          name: "Non-matching Rule",
          condition: %Rules.Condition{from_contains: "nonexistent"},
          action: %Rules.Action{type: :star},
          enabled: true
        }
      ]

      email = build_email(from: "someone@example.com")
      {:ok, _} = EmailAgent.Storage.insert_email(storage, email)

      {:ok, updated, applied_rules} = Rules.process_email(email, rules, storage)

      assert applied_rules == []
      assert updated.is_starred == false
    end

    test "returns original email when no rules defined", %{storage: storage} do
      email = build_email()
      {:ok, _} = EmailAgent.Storage.insert_email(storage, email)

      {:ok, updated, applied_rules} = Rules.process_email(email, [], storage)

      assert updated == email
      assert applied_rules == []
    end
  end

  describe "validate_rule/1" do
    test "validates correct rule" do
      rule = %Rules.Rule{
        name: "Valid Rule",
        condition: %Rules.Condition{from_contains: "test"},
        action: %Rules.Action{type: :label, label: "test"},
        enabled: true
      }

      assert :ok = Rules.validate_rule(rule)
    end

    test "returns error for rule with no conditions" do
      rule = %Rules.Rule{
        name: "Empty Condition Rule",
        condition: %Rules.Condition{},
        action: %Rules.Action{type: :star},
        enabled: true
      }

      assert {:error, :empty_condition} = Rules.validate_rule(rule)
    end

    test "returns error for move action without destination" do
      rule = %Rules.Rule{
        name: "Invalid Move Rule",
        condition: %Rules.Condition{from_contains: "test"},
        action: %Rules.Action{type: :move, destination: nil},
        enabled: true
      }

      assert {:error, :missing_destination} = Rules.validate_rule(rule)
    end

    test "returns error for label action without label" do
      rule = %Rules.Rule{
        name: "Invalid Label Rule",
        condition: %Rules.Condition{from_contains: "test"},
        action: %Rules.Action{type: :label, label: nil},
        enabled: true
      }

      assert {:error, :missing_label} = Rules.validate_rule(rule)
    end
  end

  # Helper functions

  defp build_email(overrides \\ []) do
    defaults = [
      id: "test-#{:erlang.unique_integer([:positive])}",
      message_id: "<test@example.com>",
      from: "sender@example.com",
      from_name: nil,
      to: ["recipient@example.com"],
      cc: [],
      bcc: [],
      subject: "Test Subject",
      date: DateTime.utc_now(),
      body_text: "Test body content.",
      body_html: nil,
      attachments: [],
      labels: ["inbox"],
      is_read: false,
      is_starred: false,
      raw: nil
    ]

    struct(Email, Keyword.merge(defaults, overrides))
  end
end
