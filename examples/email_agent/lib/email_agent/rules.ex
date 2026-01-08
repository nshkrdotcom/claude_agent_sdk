defmodule EmailAgent.Rules do
  @moduledoc """
  Email automation rules engine.

  Provides file-based automation rules for email processing.
  Rules are defined in JSON format and can automatically:

  - Label emails based on sender or subject
  - Move emails to folders
  - Mark emails as read
  - Star important emails

  ## Rule Format

  Rules are defined in a JSON file with the following structure:

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

  ## Condition Types

  - `from_contains` - Sender address contains string
  - `subject_contains` - Subject contains string
  - `has_attachment` - Email has attachments
  - `older_than_days` - Email is older than N days

  ## Action Types

  - `label` - Add a label to the email
  - `move` - Move to a folder
  - `mark_read` - Mark as read
  - `star` - Star the email

  ## Usage

      {:ok, rules} = Rules.load_rules("priv/rules.json")

      for email <- emails do
        {:ok, updated, applied} = Rules.process_email(email, rules, storage)
      end
  """

  alias EmailAgent.{Email, Storage}

  @default_rules_path "priv/rules.json"

  defmodule Condition do
    @moduledoc "Rule condition specification"

    @type t :: %__MODULE__{
            from_contains: String.t() | nil,
            subject_contains: String.t() | nil,
            has_attachment: boolean() | nil,
            older_than_days: non_neg_integer() | nil
          }

    defstruct [
      :from_contains,
      :subject_contains,
      :has_attachment,
      :older_than_days
    ]
  end

  defmodule Action do
    @moduledoc "Rule action specification"

    @type action_type :: :label | :move | :mark_read | :star

    @type t :: %__MODULE__{
            type: action_type(),
            label: String.t() | nil,
            destination: String.t() | nil
          }

    defstruct [:type, :label, :destination]
  end

  defmodule Rule do
    @moduledoc "Complete rule with condition and action"

    @type t :: %__MODULE__{
            name: String.t(),
            condition: EmailAgent.Rules.Condition.t(),
            action: EmailAgent.Rules.Action.t(),
            enabled: boolean()
          }

    defstruct [:name, :condition, :action, enabled: true]
  end

  @doc """
  Loads rules from a JSON file.

  Returns an empty list if the file doesn't exist.
  """
  @spec load_rules(String.t()) :: {:ok, [Rule.t()]} | {:error, term()}
  def load_rules(path \\ @default_rules_path) do
    case File.read(path) do
      {:ok, content} ->
        parse_rules_file(content)

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses a single rule from a map.
  """
  @spec parse_rule(map()) :: {:ok, Rule.t()} | {:error, atom()}
  def parse_rule(rule_map) do
    with {:ok, name} <- get_required(rule_map, "name"),
         {:ok, action_map} <- get_required(rule_map, "action"),
         {:ok, action} <- parse_action(action_map) do
      condition_map = Map.get(rule_map, "condition", %{})
      condition = parse_condition(condition_map)
      enabled = Map.get(rule_map, "enabled", true)

      {:ok,
       %Rule{
         name: name,
         condition: condition,
         action: action,
         enabled: enabled
       }}
    end
  end

  @doc """
  Checks if a rule matches an email.
  """
  @spec matches?(Rule.t(), Email.t()) :: boolean()
  def matches?(%Rule{enabled: false}, _email), do: false

  def matches?(%Rule{condition: condition}, %Email{} = email) do
    all_conditions_match?(condition, email)
  end

  @doc """
  Applies a rule's action to an email.
  """
  @spec apply_rule(Rule.t(), Email.t(), pid()) :: {:ok, Email.t()} | {:error, term()}
  def apply_rule(%Rule{action: action}, %Email{} = email, storage) do
    apply_action(action, email, storage)
  end

  @doc """
  Processes an email through all matching rules.

  Returns the updated email and a list of applied rule names.
  """
  @spec process_email(Email.t(), [Rule.t()], pid()) ::
          {:ok, Email.t(), [String.t()]}
  def process_email(%Email{} = email, rules, storage) do
    {updated_email, applied_rules} =
      Enum.reduce(rules, {email, []}, fn rule, acc ->
        try_apply_rule(rule, acc, storage)
      end)

    {:ok, updated_email, Enum.reverse(applied_rules)}
  end

  defp try_apply_rule(rule, {current_email, applied}, storage) do
    if matches?(rule, current_email) do
      do_apply_rule(rule, current_email, applied, storage)
    else
      {current_email, applied}
    end
  end

  defp do_apply_rule(rule, current_email, applied, storage) do
    case apply_rule(rule, current_email, storage) do
      {:ok, new_email} -> {new_email, [rule.name | applied]}
      {:error, _} -> {current_email, applied}
    end
  end

  @doc """
  Validates a rule for correctness.
  """
  @spec validate_rule(Rule.t()) :: :ok | {:error, atom()}
  def validate_rule(%Rule{condition: condition, action: action}) do
    with :ok <- validate_condition(condition) do
      validate_action(action)
    end
  end

  # Private functions

  defp parse_rules_file(content) do
    case Jason.decode(content) do
      {:ok, %{"rules" => rules_list}} when is_list(rules_list) ->
        parsed =
          rules_list
          |> Enum.map(&parse_rule/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, rule} -> rule end)

        {:ok, parsed}

      {:ok, _} ->
        {:error, :invalid_format}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:json_decode_error, error}}
    end
  end

  defp parse_condition(condition_map) do
    %Condition{
      from_contains: Map.get(condition_map, "from_contains"),
      subject_contains: Map.get(condition_map, "subject_contains"),
      has_attachment: Map.get(condition_map, "has_attachment"),
      older_than_days: Map.get(condition_map, "older_than_days")
    }
  end

  defp parse_action(action_map) do
    type_str = Map.get(action_map, "type")

    type =
      case type_str do
        "label" -> :label
        "move" -> :move
        "mark_read" -> :mark_read
        "star" -> :star
        _ -> nil
      end

    if type do
      {:ok,
       %Action{
         type: type,
         label: Map.get(action_map, "label"),
         destination: Map.get(action_map, "destination")
       }}
    else
      {:error, :invalid_action_type}
    end
  end

  defp get_required(map, key) do
    case Map.get(map, key) do
      nil -> {:error, String.to_atom("missing_#{key}")}
      value -> {:ok, value}
    end
  end

  defp all_conditions_match?(condition, email) do
    checks = [
      check_from_contains(condition.from_contains, email),
      check_subject_contains(condition.subject_contains, email),
      check_has_attachment(condition.has_attachment, email),
      check_older_than_days(condition.older_than_days, email)
    ]

    Enum.all?(checks)
  end

  defp check_from_contains(nil, _email), do: true

  defp check_from_contains(pattern, %Email{from: from}) do
    String.contains?(String.downcase(from || ""), String.downcase(pattern))
  end

  defp check_subject_contains(nil, _email), do: true

  defp check_subject_contains(pattern, %Email{subject: subject}) do
    String.contains?(String.downcase(subject || ""), String.downcase(pattern))
  end

  defp check_has_attachment(nil, _email), do: true

  defp check_has_attachment(expected, %Email{} = email) do
    Email.has_attachments?(email) == expected
  end

  defp check_older_than_days(nil, _email), do: true

  defp check_older_than_days(days, %Email{date: nil}), do: days > 0

  defp check_older_than_days(days, %Email{date: date}) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)
    DateTime.compare(date, cutoff) == :lt
  end

  defp apply_action(%Action{type: :label, label: label}, %Email{} = email, storage) do
    new_labels = Enum.uniq([label | email.labels])
    updated = %{email | labels: new_labels}

    case Storage.update_email(storage, email.id, %{labels: new_labels}) do
      {:ok, _} -> {:ok, updated}
      error -> error
    end
  end

  defp apply_action(%Action{type: :star}, %Email{} = email, storage) do
    updated = %{email | is_starred: true}

    case Storage.update_email(storage, email.id, %{is_starred: true}) do
      {:ok, _} -> {:ok, updated}
      error -> error
    end
  end

  defp apply_action(%Action{type: :mark_read}, %Email{} = email, storage) do
    updated = %{email | is_read: true}

    case Storage.update_email(storage, email.id, %{is_read: true}) do
      {:ok, _} -> {:ok, updated}
      error -> error
    end
  end

  defp apply_action(
         %Action{type: :move, destination: dest},
         %Email{} = email,
         storage
       ) do
    # Remove inbox, add destination
    new_labels =
      email.labels
      |> Enum.reject(&(&1 == "inbox"))
      |> Kernel.++([dest])
      |> Enum.uniq()

    updated = %{email | labels: new_labels}

    case Storage.update_email(storage, email.id, %{labels: new_labels}) do
      {:ok, _} -> {:ok, updated}
      error -> error
    end
  end

  defp validate_condition(%Condition{} = condition) do
    # At least one condition must be set
    has_condition =
      condition.from_contains != nil or
        condition.subject_contains != nil or
        condition.has_attachment != nil or
        condition.older_than_days != nil

    if has_condition do
      :ok
    else
      {:error, :empty_condition}
    end
  end

  defp validate_action(%Action{type: :label, label: nil}), do: {:error, :missing_label}
  defp validate_action(%Action{type: :move, destination: nil}), do: {:error, :missing_destination}
  defp validate_action(%Action{}), do: :ok
end
