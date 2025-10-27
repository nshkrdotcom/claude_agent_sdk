# Test Suite Refactoring: Eliminate Process.sleep with Supertester

**Date**: 2025-10-26
**Task**: Refactor streaming tests to use Supertester patterns instead of Process.sleep
**Priority**: HIGH (Improves test reliability and speed)
**Estimated Time**: 2-3 hours
**Methodology**: Test-Driven Refactoring (tests must pass at each step)

---

## CONTEXT: The Problem

Our v0.6.0 streaming tests violate **Supertester's core philosophy** by using `Process.sleep/1` for synchronization:

```elixir
# ❌ ANTI-PATTERN (found in multiple tests)
MockTransport.push_message(transport, event)
Process.sleep(50)  # Flaky! Race conditions! Non-deterministic!
```

**Why this is bad**:
1. **Flaky**: Tests can fail randomly if timing changes
2. **Slow**: Artificial delays add up (50ms × many tests)
3. **Non-deterministic**: May pass locally but fail in CI
4. **Violates Supertester principles**: We have the tools to do better!

**Impact**: Found in ~15 test cases across Client streaming tests.

---

## REQUIRED READING (In Order)

### 1. Supertester Documentation (CRITICAL)

**Location**: `~/p/g/n/supertester/`

**Must Read Files**:

1. **README.md** (245 lines) - ✅ Already read above
   - Core philosophy: Zero Process.sleep
   - Key features overview
   - Quick examples

2. **MANUAL.md** (Complete user manual)
   ```bash
   cat ~/p/g/n/supertester/MANUAL.md
   ```
   - Detailed function signatures
   - Best practices
   - Common patterns
   - Recipes for testing scenarios

3. **Source Code** (for deep understanding):
   ```bash
   # Core helpers
   ~/p/g/n/supertester/lib/supertester/genserver_helpers.ex
   ~/p/g/n/supertester/lib/supertester/otp_helpers.ex
   ~/p/g/n/supertester/lib/supertester/assertions.ex

   # Test examples showing proper usage
   ~/p/g/n/supertester/test/supertester/*_test.exs
   ```

**Key Functions to Understand**:
- `setup_isolated_genserver/3` - Start isolated GenServer
- `cast_and_sync/2` - Deterministic cast synchronization
- `assert_genserver_state/3` - Wait for state condition
- `eventually/2` - Retry until condition met (already in our SupertesterCase)
- `assert_no_process_leaks/1` - Verify cleanup

### 2. Our Current Test Files (To Refactor)

**Primary Target**:
```bash
test/claude_agent_sdk/client_streaming_test.exs (381 lines, 20 tests)
```

**Issues to Fix**:
- Line 79: `Process.sleep(50)` after push_message
- Line 98: `Process.sleep(50)` after push_message
- Line 116: `Process.sleep(50)` after push_message
- Line 129: `Process.sleep(50)` after push_message
- Line 142: `Process.sleep(50)` after push_message
- Line 155-156: `Process.sleep(25)` in two places
- Line 174: `Process.sleep(50)` after message sequence

**Pattern**: Every time we push a message to MockTransport, we sleep hoping it gets processed.

**Secondary Targets** (if time):
```bash
test/claude_agent_sdk/streaming_facade_test.exs (211 lines, 13 tests)
# Less critical - fewer Process.sleep instances
```

### 3. Our Test Infrastructure (Context)

**Files to understand**:
```bash
# What we're testing
lib/claude_agent_sdk/client.ex (Lines 1394-1481: Stream event handling)

# Our test support
test/support/mock_transport.ex (95 lines)
test/support/supertester_case.ex (56 lines)

# How tests currently work
test/claude_agent_sdk/client_streaming_test.exs (setup blocks, patterns)
```

---

## SUPERTESTER PHILOSOPHY APPLIED TO OUR TESTS

### Key Principles

#### 1. **Zero Process.sleep** ✅
**Instead of guessing timing, wait for observable state changes**

Before (flaky):
```elixir
MockTransport.push_message(transport, event)
Process.sleep(50)  # Hope it's processed?
```

After (deterministic):
```elixir
MockTransport.push_message(transport, event)

# Wait for specific state change
assert_genserver_state(client, fn state ->
  state.accumulated_text != ""
end)

# Or wait for side effect
eventually(fn ->
  # Check that event was processed
  state = :sys.get_state(client)
  state.accumulated_text =~ "Hello"
end)
```

#### 2. **Isolated Execution** ✅
**We're already doing this via SupertesterCase**

Our setup:
```elixir
use ClaudeAgentSDK.SupertesterCase
# → use Supertester.UnifiedTestFoundation, isolation: :basic
# → Provides isolated process namespace
# → Automatic cleanup
```

**Good!** But we should verify isolation level is appropriate.

#### 3. **OTP-Aware Assertions** 📝
**Use GenServer-specific assertions instead of generic checks**

Current (weak):
```elixir
assert Process.alive?(client)
```

Better (strong):
```elixir
assert_genserver_state(client, fn state ->
  # Verify specific state condition
  is_binary(state.accumulated_text) and
  is_nil(state.active_subscriber)
end)
```

#### 4. **Deterministic Async Operations** 📝
**Make Client a TestableGenServer for automatic sync**

Option 1: Use cast_and_sync (current approach):
```elixir
# Instead of
GenServer.cast(client, {:some_cast})
Process.sleep(50)

# Use
cast_and_sync(client, {:some_cast})
```

Option 2: Make Client implement TestableGenServer behavior:
```elixir
defmodule Client do
  use GenServer
  @behaviour Supertester.TestableGenServer  # Add this

  # Automatically adds handle_call({:__sync__, ref}, _from, state)
  # Tests can then use cast_and_sync/2
end
```

---

## SYSTEMATIC REFACTORING PROCESS (TDD)

### Phase 1: Preparation

#### Step 1: Create Tracking Branch
```bash
git checkout -b refactor/supertester-tests
```

#### Step 2: Read Supertester MANUAL
```bash
cat ~/p/g/n/supertester/MANUAL.md | less
# Focus on:
# - GenServerHelpers section (cast_and_sync)
# - Assertions section (assert_genserver_state)
# - Best practices
```

#### Step 3: Identify All Process.sleep Instances
```bash
grep -n "Process.sleep" test/claude_agent_sdk/client_streaming_test.exs
# Expected: ~7-8 instances
```

### Phase 2: Refactor Each Test (TDD)

**For EACH test with Process.sleep**:

#### Step 1: Run Test (Baseline)
```bash
mix test test/claude_agent_sdk/client_streaming_test.exs:LINE_NUMBER
# Should PASS (current implementation)
```

#### Step 2: Replace Process.sleep with Supertester Helper

**Pattern 1: Waiting for State Change**

Before:
```elixir
test "handles text_delta events", %{transport: transport} do
  event = %{"type" => "content_block_delta", ...}

  MockTransport.push_message(transport, Jason.encode!(event))
  Process.sleep(50)  # ❌
end
```

After:
```elixir
test "handles text_delta events", %{client: client, transport: transport} do
  event = %{"type" => "content_block_delta", ...}

  MockTransport.push_message(transport, Jason.encode!(event))

  # ✅ Wait for state to reflect the event was processed
  assert_genserver_state(client, fn state ->
    # Event should have updated accumulated_text
    String.contains?(state.accumulated_text, "Hello")
  end, timeout: 1000)
end
```

**Pattern 2: Waiting for Side Effects**

Before:
```elixir
test "accumulates text across deltas", %{transport: transport} do
  deltas = ["Hello", " ", "World"]

  for text <- deltas do
    MockTransport.push_message(transport, make_text_delta(text))
  end

  Process.sleep(50)  # ❌
end
```

After:
```elixir
test "accumulates text across deltas", %{client: client, transport: transport} do
  deltas = ["Hello", " ", "World"]

  for text <- deltas do
    MockTransport.push_message(transport, make_text_delta(text))
  end

  # ✅ Wait for final accumulated state
  eventually(fn ->
    state = :sys.get_state(client)
    state.accumulated_text == "Hello World"
  end, timeout: 1000)

  # Then assert
  assert_genserver_state(client, fn state ->
    state.accumulated_text == "Hello World"
  end)
end
```

**Pattern 3: Just Verifying No Crash**

Before:
```elixir
test "handles message_stop event", %{transport: transport} do
  MockTransport.push_message(transport, %{"type" => "message_stop"})
  Process.sleep(50)  # Just checking it doesn't crash
end
```

After:
```elixir
test "handles message_stop event", %{client: client, transport: transport} do
  MockTransport.push_message(transport, %{"type" => "message_stop"})

  # ✅ Wait for state transition (message completion resets active_subscriber)
  eventually(fn ->
    state = :sys.get_state(client)
    state.active_subscriber == nil
  end)

  # Verify the state is correct
  assert_genserver_state(client, fn state ->
    state.active_subscriber == nil
  end)
end
```

#### Step 3: Run Test (Should Still Pass)
```bash
mix test test/claude_agent_sdk/client_streaming_test.exs:LINE_NUMBER
# Must PASS - if not, fix the refactored code
```

#### Step 4: Verify No Regression
```bash
mix test test/claude_agent_sdk/client_streaming_test.exs
# All 20 tests must still pass
```

#### Step 5: Commit
```bash
git add test/claude_agent_sdk/client_streaming_test.exs
git commit -m "refactor(tests): Replace Process.sleep with assert_genserver_state in test X

- Replaced timing-based sync with state-based sync
- Uses assert_genserver_state to wait for state changes
- Test is now deterministic and faster
- Follows Supertester best practices

Test still passes: mix test ...exs:LINE"
```

### Phase 3: Add Enhanced Assertions

After removing all Process.sleep, enhance tests with better assertions:

#### Add Process Leak Checks

```elixir
describe "stream event handling" do
  setup do
    # ... existing setup ...

    # Track initial process count
    on_exit(fn ->
      # Verify no process leaks
      assert_no_process_leaks()
    end)

    %{client: client, transport: transport}
  end
end
```

#### Add State Validation

```elixir
test "resets accumulated text on message_stop", %{client: client, transport: transport} do
  # Send text deltas
  MockTransport.push_message(transport, text_delta("Hello"))

  eventually(fn ->
    :sys.get_state(client).accumulated_text == "Hello"
  end)

  # Send message_stop
  MockTransport.push_message(transport, message_stop())

  # ✅ Verify state is reset
  assert_genserver_state(client, fn state ->
    state.accumulated_text == "Hello" and  # Preserved
    state.active_subscriber == nil  # Reset
  end)
end
```

### Phase 4: Verification

#### Run Full Suite
```bash
mix test
# Expected: 602 tests passing (no new failures)
# May be FASTER due to removing sleep delays
```

#### Check for Remaining Process.sleep
```bash
grep -r "Process.sleep" test/claude_agent_sdk/*streaming*.exs
# Expected: 0 results (all removed)
```

#### Verify Test Speed Improvement
```bash
# Before refactoring
time mix test test/claude_agent_sdk/client_streaming_test.exs
# Note the time

# After refactoring
time mix test test/claude_agent_sdk/client_streaming_test.exs
# Should be faster (removed artificial delays)
```

---

## DETAILED REFACTORING GUIDE

### Test File: client_streaming_test.exs

**Current Issues** (line numbers):

```elixir
# Line 79 - handles message_start event
Process.sleep(50)
# FIX: Wait for state.initialized or use eventually

# Line 98 - handles text_delta events
Process.sleep(50)
# FIX: Wait for accumulated_text to change

# Line 116 - handles message_stop event
Process.sleep(50)
# FIX: Wait for active_subscriber to be nil

# Line 129 - handles tool_use_start event
Process.sleep(50)
# FIX: Can remove - event is fire-and-forget

# Line 142 - handles tool_input_delta events
Process.sleep(50)
# FIX: Can remove or wait for state

# Line 155-156 - accumulates text across deltas
Process.sleep(25) twice
# FIX: Wait for final accumulated_text value

# Line 174 - resets accumulated text on message_stop
Process.sleep(25)
# FIX: Wait for state.accumulated_text reset
```

### Refactoring Template for Each Test

```elixir
# BEFORE
test "some test", %{transport: transport} do
  MockTransport.push_message(transport, event)
  Process.sleep(50)
  # implicit: assume processing happened
end

# AFTER (Option 1: Assert state change)
test "some test", %{client: client, transport: transport} do
  MockTransport.push_message(transport, event)

  # Explicitly wait for observable state change
  assert_genserver_state(client, fn state ->
    # Define the condition that proves event was processed
    state.some_field == expected_value
  end, timeout: 1000)
end

# AFTER (Option 2: Eventually helper)
test "some test", %{client: client, transport: transport} do
  MockTransport.push_message(transport, event)

  # Wait for condition
  eventually(fn ->
    state = :sys.get_state(client)
    state.some_field == expected_value
  end, timeout: 1000)

  # Then make assertions
  assert_genserver_state(client, fn state ->
    state.some_field == expected_value
  end)
end

# AFTER (Option 3: No wait needed)
test "some test that just checks no crash", %{transport: transport} do
  MockTransport.push_message(transport, event)

  # If we're just checking it doesn't crash, no sync needed
  # The test passing means it worked
end
```

---

## SPECIFIC REFACTORINGS NEEDED

### Test 1: "handles message_start event" (Line 65-80)

**Current Code**:
```elixir
test "handles message_start event", %{transport: transport} do
  event = %{
    "type" => "message_start",
    "message" => %{
      "model" => "claude-sonnet-4-5",
      "role" => "assistant",
      "usage" => %{"input_tokens" => 10, "output_tokens" => 0}
    }
  }

  MockTransport.push_message(transport, Jason.encode!(event))
  Process.sleep(50)  # ❌
end
```

**Refactored**:
```elixir
test "handles message_start event", %{client: client, transport: transport} do
  event = %{
    "type" => "message_start",
    "message" => %{
      "model" => "claude-sonnet-4-5",
      "role" => "assistant",
      "usage" => %{"input_tokens" => 10, "output_tokens" => 0}
    }
  }

  MockTransport.push_message(transport, Jason.encode!(event))

  # ✅ Event is informational only, just verify no crash
  # If we want to verify it was processed:
  eventually(fn ->
    # Check some state that proves message_start was handled
    # (message_start doesn't change much state, so this might just be checking alive)
    Process.alive?(client)
  end)
end
```

### Test 2: "handles text_delta events" (Line 82-99)

**Current Code**:
```elixir
test "handles text_delta events", %{transport: transport} do
  events = [
    %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => "Hello"}},
    %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => " World"}}
  ]

  for event <- events do
    MockTransport.push_message(transport, Jason.encode!(event))
  end

  Process.sleep(50)  # ❌
end
```

**Refactored**:
```elixir
test "handles text_delta events", %{client: client, transport: transport} do
  events = [
    %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => "Hello"}},
    %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => " World"}}
  ]

  for event <- events do
    MockTransport.push_message(transport, Jason.encode!(event))
  end

  # ✅ Wait for accumulated text to contain both deltas
  assert_genserver_state(client, fn state ->
    state.accumulated_text == "Hello World"
  end, timeout: 1000)
end
```

### Test 3: "handles message_stop event" (Line 108-117)

**Current Code**:
```elixir
test "handles message_stop event", %{transport: transport} do
  event = %{"type" => "message_stop"}
  MockTransport.push_message(transport, Jason.encode!(event))
  Process.sleep(50)  # ❌
end
```

**Refactored**:
```elixir
test "handles message_stop event", %{client: client, transport: transport} do
  event = %{"type" => "message_stop"}

  MockTransport.push_message(transport, Jason.encode!(event))

  # ✅ Wait for stream completion (active_subscriber becomes nil)
  assert_genserver_state(client, fn state ->
    state.active_subscriber == nil
  end, timeout: 1000)
end
```

### Test 4: "accumulates text across multiple deltas" (Line 145-177)

**Current Code**:
```elixir
test "accumulates text across multiple deltas", %{transport: transport} do
  deltas = ["Hello", " ", "World", "!"]

  for text <- deltas do
    event = %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}}
    MockTransport.push_message(transport, Jason.encode!(event))
  end

  Process.sleep(50)  # ❌
end
```

**Refactored**:
```elixir
test "accumulates text across multiple deltas", %{client: client, transport: transport} do
  deltas = ["Hello", " ", "World", "!"]

  for text <- deltas do
    event = %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}}
    MockTransport.push_message(transport, Jason.encode!(event))
  end

  # ✅ Wait for all deltas to be accumulated
  assert_genserver_state(client, fn state ->
    state.accumulated_text == "Hello World!"
  end, timeout: 1000)

  # Additional assertion: verify it's exactly right
  final_state = :sys.get_state(client)
  assert final_state.accumulated_text == "Hello World!"
end
```

### Test 5: "resets accumulated text on message_stop" (Line 161-178)

**Current Code**:
```elixir
test "resets accumulated text on message_stop", %{transport: transport} do
  event1 = %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => "Hello"}}
  MockTransport.push_message(transport, Jason.encode!(event1))
  Process.sleep(25)  # ❌

  event2 = %{"type" => "message_stop"}
  MockTransport.push_message(transport, Jason.encode!(event2))
  Process.sleep(25)  # ❌
end
```

**Refactored**:
```elixir
test "resets accumulated text on message_stop", %{client: client, transport: transport} do
  # Send text delta
  event1 = %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => "Hello"}}
  MockTransport.push_message(transport, Jason.encode!(event1))

  # ✅ Wait for text to be accumulated
  assert_genserver_state(client, fn state ->
    state.accumulated_text == "Hello"
  end)

  # Send message_stop
  event2 = %{"type" => "message_stop"}
  MockTransport.push_message(transport, Jason.encode!(event2))

  # ✅ Wait for completion (active_subscriber reset)
  assert_genserver_state(client, fn state ->
    state.active_subscriber == nil
  end)

  # Verify accumulated text was preserved (not reset to "")
  # (Based on handle_stream_completion logic)
  final_state = :sys.get_state(client)
  assert final_state.accumulated_text == "Hello"
end
```

---

## SETUP IMPROVEMENTS

### Current Setup (Needs client in context)

Many tests receive `%{transport: transport}` but need `client` to use assert_genserver_state.

**Fix the setup block**:

```elixir
describe "stream event handling" do
  setup do
    options = %Options{include_partial_messages: true}

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    transport =
      receive do
        {:mock_transport_started, t} -> t
      end

    # ✅ Return BOTH client and transport
    %{client: client, transport: transport}
  end

  # Now tests can use: test "...", %{client: client, transport: transport}
end
```

**Already done in most tests!** ✅ Just need to use `client` parameter.

---

## ADVANCED: Make Client a TestableGenServer (Optional)

### Option A: Add TestableGenServer Behavior to Client

**File**: `lib/claude_agent_sdk/client.ex`

**Add**:
```elixir
defmodule ClaudeAgentSDK.Client do
  use GenServer

  # Add this for tests
  if Mix.env() == :test do
    @behaviour Supertester.TestableGenServer

    # Automatically handled by Supertester:
    # - Adds handle_call({:__sync__, ref}, _from, state)
    # - Allows cast_and_sync/2 in tests
  end

  # ... rest of module
end
```

**Then in tests, use**:
```elixir
# Instead of waiting manually
MockTransport.push_message(transport, event)
assert_genserver_state(client, fn state -> ... end)

# Can use (if TestableGenServer added)
GenServer.cast(client, {:some_internal_cast})
cast_and_sync(client)  # Waits deterministically
```

### Option B: Keep Current Approach (Simpler)

Use `assert_genserver_state` and `eventually` without modifying Client.

**Recommendation**: **Option B** - simpler, less invasive.

---

## HELPER FUNCTIONS TO ADD

### Add to test file for cleaner code:

```elixir
# test/claude_agent_sdk/client_streaming_test.exs

defmodule ClaudeAgentSDK.ClientStreamingTest do
  use ClaudeAgentSDK.SupertesterCase

  # ... tests ...

  ## Test Helpers

  defp text_delta(text) do
    %{
      "type" => "content_block_delta",
      "delta" => %{"type" => "text_delta", "text" => text},
      "index" => 0
    }
  end

  defp message_start(opts \\ []) do
    %{
      "type" => "message_start",
      "message" => %{
        "model" => Keyword.get(opts, :model, "claude-sonnet-4-5"),
        "role" => "assistant",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 0}
      }
    }
  end

  defp message_stop do
    %{"type" => "message_stop"}
  end

  defp push_and_wait_for_state(transport, client, event, state_check) do
    MockTransport.push_message(transport, Jason.encode!(event))
    assert_genserver_state(client, state_check, timeout: 1000)
  end
end
```

---

## ACCEPTANCE CRITERIA

Before considering refactoring complete:

### Must Have ✅
- [ ] Zero `Process.sleep` calls in streaming tests
- [ ] All tests still passing (602/602)
- [ ] Using `assert_genserver_state` for state verification
- [ ] Using `eventually` for condition waiting
- [ ] No new flaky tests introduced

### Should Have 📝
- [ ] Tests run faster (measure before/after)
- [ ] Better error messages from OTP-aware assertions
- [ ] Process leak detection in setup teardown
- [ ] Helper functions reduce duplication

### Nice to Have (Optional) 🎁
- [ ] Client implements TestableGenServer
- [ ] All tests use `async: true` explicitly
- [ ] Performance assertions on critical paths
- [ ] Chaos testing for subscriber queue

---

## STEP-BY-STEP EXECUTION PLAN

### Session 1: Setup & First Test (30 min)

```bash
# 1. Create branch
git checkout -b refactor/supertester-tests

# 2. Read Supertester MANUAL (10 min)
cat ~/p/g/n/supertester/MANUAL.md | less

# 3. Find all Process.sleep (5 min)
grep -n "Process.sleep" test/claude_agent_sdk/client_streaming_test.exs > /tmp/sleeps.txt
cat /tmp/sleeps.txt

# 4. Refactor first test (10 min)
#    - Line 79: handles message_start event
#    - Replace Process.sleep with assertion
#    - Run test: mix test ...exs:65

# 5. Commit (5 min)
git add test/claude_agent_sdk/client_streaming_test.exs
git commit -m "refactor(tests): Remove Process.sleep from message_start test"
```

### Session 2: Refactor Remaining Tests (60 min)

```bash
# For each remaining Process.sleep:
for line in 98 116 129 142 155 156 174; do
  # 1. Identify test containing line
  # 2. Refactor with assert_genserver_state or eventually
  # 3. Run test: mix test ...exs:LINE
  # 4. Commit
done

# Verify all tests pass
mix test test/claude_agent_sdk/client_streaming_test.exs
```

### Session 3: Add Enhanced Assertions (30 min)

```bash
# 1. Add process leak checks
# 2. Add helper functions
# 3. Enhance state assertions
# 4. Run full suite: mix test
# 5. Measure performance improvement
# 6. Commit
```

### Session 4: Verification & Documentation (20 min)

```bash
# 1. Run full suite 3x (check for flakiness)
for i in 1 2 3; do
  mix test test/claude_agent_sdk/client_streaming_test.exs
done

# 2. Verify no Process.sleep remains
grep "Process.sleep" test/claude_agent_sdk/client_streaming_test.exs
# Expected: no results

# 3. Update continuation_prompt.md with refactoring notes
# 4. Final commit

# 5. Merge to main
git checkout main
git merge refactor/supertester-tests
```

---

## EXPECTED OUTCOMES

### Before Refactoring
- 20 tests in client_streaming_test.exs
- ~7-8 Process.sleep(50) calls
- Artificial delays: ~350-400ms total
- Potential flakiness: MEDIUM risk

### After Refactoring
- 20 tests in client_streaming_test.exs ✅
- 0 Process.sleep calls ✅
- Artificial delays: 0ms ✅
- Potential flakiness: LOW risk ✅
- Test speed: 10-20% faster ✅
- Test reliability: MUCH higher ✅

---

## REFERENCE: Supertester Functions to Use

### From GenServerHelpers

```elixir
# Deterministic cast synchronization
cast_and_sync(genserver, message)

# Send multiple casts and sync
cast_all_and_sync(genserver, [msg1, msg2, msg3])
```

### From Assertions

```elixir
# Wait for state condition
assert_genserver_state(genserver, fn state ->
  state.field == value
end, timeout: 1000)

# Check process alive
assert_process_alive(pid)
assert_process_dead(pid)

# Check no leaks
assert_no_process_leaks()
```

### From OTPHelpers

```elixir
# Start isolated genserver (auto cleanup)
{:ok, pid} = setup_isolated_genserver(MyGenServer, init_args)

# Start isolated supervisor
{:ok, sup} = setup_isolated_supervisor(MySupervisor)
```

### From SupertesterCase (Already Available)

```elixir
# Retry until condition met
eventually(fn ->
  state = :sys.get_state(genserver)
  state.field == value
end, timeout: 1000, interval: 25)
```

---

## TESTING THE REFACTORING

### Test Each Change Immediately

```bash
# After each refactoring
mix test test/claude_agent_sdk/client_streaming_test.exs:LINE_NUMBER

# Should PASS
```

### Verify No Regressions

```bash
# After all refactorings
mix test test/claude_agent_sdk/client_streaming_test.exs

# Expected: 20/20 passing (was 20/20 before)
```

### Measure Speed Improvement

```bash
# Before
time mix test test/claude_agent_sdk/client_streaming_test.exs
# Note: X.XX seconds

# After
time mix test test/claude_agent_sdk/client_streaming_test.exs
# Should be: < X.XX seconds (faster)
```

### Check for Flakiness

```bash
# Run 10 times to verify determinism
for i in {1..10}; do
  mix test test/claude_agent_sdk/client_streaming_test.exs || echo "FAIL $i"
done

# Expected: 10 successes, 0 failures
```

---

## TROUBLESHOOTING

### Issue: assert_genserver_state Times Out

**Problem**: State condition never becomes true

**Debug**:
```elixir
# Add debug output before assertion
state = :sys.get_state(client)
IO.inspect(state, label: "Client state before assertion")

assert_genserver_state(client, fn state ->
  IO.inspect(state.accumulated_text, label: "Accumulated text")
  state.accumulated_text == "expected"
end)
```

**Solutions**:
1. Check if event is actually being sent
2. Verify event format is correct
3. Check if handler is being called (add logging)
4. Increase timeout if processing is slow

### Issue: Tests Become Slower

**Problem**: Waiting for state with high timeout

**Solution**: Use shorter timeouts and verify faster
```elixir
# Instead of default 5000ms
assert_genserver_state(client, fn state -> ... end, timeout: 500)
```

### Issue: Eventually Always Times Out

**Problem**: Condition logic is wrong

**Debug**:
```elixir
eventually(fn ->
  state = :sys.get_state(client)
  result = state.field == value
  IO.inspect({state.field, value, result}, label: "Eventually check")
  result
end)
```

---

## FILES TO MODIFY

### Primary (Must Refactor)
1. `test/claude_agent_sdk/client_streaming_test.exs`
   - Remove 7-8 Process.sleep calls
   - Add client to test parameters
   - Use assert_genserver_state

### Secondary (If Time)
2. `test/claude_agent_sdk/streaming_facade_test.exs`
   - Check for any Process.sleep
   - Add better assertions

### Infrastructure (Optional Enhancement)
3. `lib/claude_agent_sdk/client.ex`
   - Add TestableGenServer behavior (if going Option A)

4. `test/support/supertester_case.ex`
   - Add custom helpers specific to streaming tests

---

## COMMIT STRATEGY

### Commit After Each Test Refactored

```bash
git add test/claude_agent_sdk/client_streaming_test.exs
git commit -m "refactor(tests): Remove Process.sleep from [test name]

Replaced timing-based sync with state-based verification:
- Before: Process.sleep(50) hoping event processed
- After: assert_genserver_state waiting for state change

Test verified passing:
  mix test test/claude_agent_sdk/client_streaming_test.exs:LINE

Follows Supertester best practices (zero sleep, deterministic sync).
"
```

### Final Commit After All Refactored

```bash
git add test/claude_agent_sdk/client_streaming_test.exs
git commit -m "refactor(tests): Complete Supertester refactoring - eliminate all Process.sleep

Removed all Process.sleep calls from streaming tests (7 instances).

Changes:
- Replaced Process.sleep(50) with assert_genserver_state/3
- Using eventually/2 for condition-based waiting
- Added helper functions for common event patterns
- Enhanced assertions with state verification

Benefits:
- Deterministic: No more timing-dependent failures
- Faster: Removed 350-400ms of artificial delays
- Reliable: Tests wait for actual state changes
- Follows Supertester philosophy

Verification:
- All 602 tests passing
- 0 Process.sleep in streaming tests
- Ran 10x without failures (deterministic)
- Test suite 15% faster

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
"
```

---

## QUICK REFERENCE: Process.sleep → Supertester Patterns

| Situation | Before (❌) | After (✅) |
|-----------|-------------|-----------|
| Wait for state change | `Process.sleep(50)` | `assert_genserver_state(pid, fn s -> s.field == val end)` |
| Wait for async operation | `Process.sleep(100)` | `cast_and_sync(pid, msg)` |
| Wait for condition | `Process.sleep(50)` | `eventually(fn -> condition end)` |
| Just checking no crash | `Process.sleep(50)` | Remove sleep (test passing = success) |
| Wait for multiple events | `Process.sleep(100)` | `eventually(fn -> all_processed? end)` |

---

## SUCCESS METRICS

### Quantitative
- [ ] 0 Process.sleep in streaming tests (was ~8)
- [ ] 602 tests passing (no regressions)
- [ ] Test execution 10-20% faster
- [ ] 10 consecutive runs with 0 failures (was: possible flakes)

### Qualitative
- [ ] Tests are more readable (clear state expectations)
- [ ] Better error messages (OTP-aware assertions)
- [ ] Easier to debug (can inspect state on failure)
- [ ] Follows Supertester best practices

---

## FINAL CHECKLIST

Before merging refactoring:

- [ ] Read Supertester MANUAL.md
- [ ] Identify all Process.sleep instances (7-8)
- [ ] Refactor each test one by one
- [ ] Each test passes after refactoring
- [ ] Full suite passes (602/602)
- [ ] No Process.sleep remains in streaming tests
- [ ] Tests run faster (measure time)
- [ ] Run suite 10x to verify no flakes
- [ ] Commit with detailed message
- [ ] Update continuation_prompt.md

---

**Timeline**: 2-3 hours for complete refactoring
**Risk**: LOW (tests verify correctness at each step)
**Benefit**: HIGH (more reliable, faster, better tests)
**Priority**: HIGH (improves test suite quality significantly)

**Recommended**: Do this refactoring before v0.6.0 release to ensure test suite reliability.
