# Document Generation Example

AI-powered document generation using the Claude Agent SDK and Elixir.

> **Reference:** This example is inspired by the [claude-agent-sdk-demos](https://github.com/anthropics/claude-agent-sdk-demos) project, specifically the Excel demo and resume generator demos.

## What This Example Demonstrates

This Mix application showcases how to:

- Generate professional Excel spreadsheets programmatically using `elixlsx`
- Integrate with Claude Agent SDK for AI-powered document creation
- Parse natural language specifications into structured data
- Create multi-sheet workbooks with formulas and professional styling
- Build reusable document templates (budget trackers, workout logs)

## Features

### Excel Generation (`DocumentGeneration.Excel`)

- **Multi-sheet workbooks** - Create workbooks with multiple related sheets
- **Formula support** - Add Excel formulas with proper syntax (`=SUM(A1:A10)`)
- **Professional styling** - Headers, colors, borders, number formatting
- **Currency/percentage formatting** - Proper display of financial data
- **Frozen panes** - Keep headers visible while scrolling
- **Row/column sizing** - Custom widths and heights

### AI-Powered Generation (`DocumentGeneration.ClaudeIntegration`)

- **Natural language parsing** - Describe your document in plain English
- **Streaming responses** - Real-time feedback during generation
- **Interactive sessions** - Refine requirements through conversation
- **Multiple document types** - Budget trackers, workout logs, and more

### Predefined Templates

1. **Budget Tracker** (`DocumentGeneration.Excel.budget_tracker/1`)
   - Category-based expense tracking
   - Automatic variance calculations
   - Percentage of budget formulas
   - Professional financial styling

2. **Workout Log** (`DocumentGeneration.Excel.workout_log/1`)
   - Date-based workout tracking
   - Duration and calorie logging
   - Summary statistics sheet
   - Cross-sheet formula references

## Installation

1. Ensure you have Elixir 1.14+ installed
2. Navigate to this directory:
   ```bash
   cd examples/document_generation
   ```
3. Install dependencies:
   ```bash
   mix deps.get
   ```

## Quick Start

### Run the Demo

Generate sample documents to see the features in action:

```bash
mix generate.demo
```

This creates:
- `output/demo_budget.xlsx` - Sample budget tracker
- `output/demo_workout.xlsx` - Sample workout log

### Generate a Budget Tracker

From natural language:
```bash
mix generate.budget "Housing $1500, Food $600, Transport $400"
```

With actual spending:
```bash
mix generate.budget "Rent: $1200 budget $1150 actual, Utilities: $200 budget $185 actual"
```

### Generate a Workout Log

```bash
mix generate.workout "Jan 1 Running 30min 300cal, Jan 2 Weights 45min 200cal"
```

### AI-Powered Generation (Requires API Key)

Use Claude to interpret complex requirements:

```bash
# Budget from description
mix generate.budget --ai "Create a monthly budget for a college student living off-campus"

# Workout plan
mix generate.workout --ai "Generate a week of workouts for someone training for a 5K"
```

### Interactive Mode

Start a conversation with Claude to refine your document:

```bash
mix generate.budget --interactive
```

## Programmatic Usage

### Basic Excel Generation

```elixir
alias DocumentGeneration.Excel

# Create a simple spreadsheet
Excel.create_workbook("Report")
|> Excel.add_sheet("Data")
|> Excel.set_row("Data", 1, ["Name", "Value"], bold: true)
|> Excel.set_row("Data", 2, ["Revenue", 50000])
|> Excel.set_row("Data", 3, ["Expenses", 35000])
|> Excel.set_formula("Data", "B4", "B2-B3")
|> Excel.write_to_file("report.xlsx")
```

### Using Templates

```elixir
# Budget tracker
categories = [
  %{name: "Housing", budget: 1500, actual: 1450},
  %{name: "Food", budget: 600, actual: 580}
]

{:ok, workbook} = DocumentGeneration.create_budget_tracker(categories)
DocumentGeneration.save(workbook, "budget.xlsx")

# Workout log
workouts = [
  %{date: ~D[2025-01-01], exercise: "Running", duration: 30, calories: 300}
]

{:ok, workbook} = DocumentGeneration.create_workout_log(workouts)
DocumentGeneration.save(workbook, "workout.xlsx")
```

### From Natural Language

```elixir
# Parse specification and generate
spec = "Monthly Budget: Housing $1500, Food $600, Transport $400"
{:ok, workbook} = DocumentGeneration.generate_budget(spec)
DocumentGeneration.save(workbook, "budget.xlsx")
```

### With Claude AI

```elixir
alias DocumentGeneration.ClaudeIntegration

# Generate with AI interpretation
{:ok, workbook} = ClaudeIntegration.generate_document(
  "Create a budget for a small startup with typical expenses",
  type: :budget_tracker,
  model: "sonnet"
)
```

## Project Structure

```
document_generation/
├── lib/
│   ├── document_generation.ex          # Main module
│   ├── document_generation/
│   │   ├── excel.ex                    # Excel generation (elixlsx wrapper)
│   │   ├── styles.ex                   # Styling utilities
│   │   ├── generator.ex                # Parsing and generation
│   │   └── claude_integration.ex       # Claude SDK integration
│   └── mix/tasks/
│       ├── generate.budget.ex          # Budget generator task
│       ├── generate.workout.ex         # Workout log task
│       └── generate.demo.ex            # Demo task
├── test/
│   └── document_generation/
│       ├── excel_test.exs              # Excel generation tests
│       ├── generator_test.exs          # Parser tests
│       └── styles_test.exs             # Styling tests
├── mix.exs
└── README.md
```

## Dependencies

| Dependency | Purpose |
|------------|---------|
| `elixlsx` | Excel file generation (.xlsx format) |
| `claude_agent_sdk` | Integration with Claude AI |
| `dialyxir` | Static type checking (dev only) |
| `credo` | Code quality analysis (dev/test only) |

## Example Output

### Budget Tracker

The budget tracker generates an Excel file with:

| Category | Budget | Actual | Variance | % of Budget |
|----------|--------|--------|----------|-------------|
| Housing | $1,500.00 | $1,450.00 | $-50.00 | 96.7% |
| Food | $600.00 | $580.00 | $-20.00 | 96.7% |
| Transport | $400.00 | $420.00 | $20.00 | 105.0% |
| **TOTAL** | **$2,500.00** | **$2,450.00** | **$-50.00** | **98.0%** |

Features:
- Blue header row with white text
- Currency formatting
- Variance formulas (`=C2-B2`)
- Percentage formulas (`=C2/B2`)
- Green/red conditional formatting for variance
- SUM formulas in totals row

### Workout Log

The workout log generates a multi-sheet workbook:

**Workouts Sheet:**
| Date | Exercise | Duration (min) | Calories |
|------|----------|----------------|----------|
| 2025-01-01 | Running | 30 | 300 |
| 2025-01-02 | Weights | 45 | 200 |

**Summary Sheet:**
| Metric | Value |
|--------|-------|
| Total Workouts | 2 |
| Total Duration (min) | =SUM(Workouts!C2:C3) |
| Total Calories | =SUM(Workouts!D2:D3) |
| Average Duration | =AVERAGE(Workouts!C2:C3) |

## Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/document_generation/excel_test.exs
```

## Code Quality

```bash
# Format code
mix format

# Run Credo
mix credo

# Run Dialyzer (first run will be slow)
mix dialyzer
```

## Extending

### Adding New Document Types

1. Create a new function in `DocumentGeneration.Excel`:
   ```elixir
   def invoice(items) do
     create_workbook("Invoice")
     |> add_sheet("Invoice")
     |> setup_invoice_headers()
     |> add_invoice_items(items)
   end
   ```

2. Add parsing in `DocumentGeneration.Generator`:
   ```elixir
   def parse_invoice_spec(spec) do
     # Extract invoice items from natural language
   end
   ```

3. Create a Mix task in `lib/mix/tasks/generate.invoice.ex`

### Custom Styling

```elixir
alias DocumentGeneration.Styles

# Create custom header style
custom_header = Styles.header_style(color: "#FF5722", font_size: 14)

# Merge styles
combined = Styles.merge_styles(
  Styles.currency_style(),
  Styles.positive_style()
)
```

## Troubleshooting

### "Application not started" Error

Ensure you start required applications:
```elixir
Application.ensure_all_started(:elixlsx)
Application.ensure_all_started(:claude_agent_sdk)
```

### Formula Errors in Excel

- Check cell references are correct
- Ensure referenced cells exist before the formula
- Use `Styles.cell_reference/2` for dynamic references

### Claude Integration Issues

- Verify `ANTHROPIC_API_KEY` is set
- Check you're authenticated with `claude login`
- Try simpler prompts first

## License

MIT - See the main project LICENSE file.

---

Built with the [Claude Agent SDK](https://github.com/nshkrdotcom/claude_agent_sdk)
