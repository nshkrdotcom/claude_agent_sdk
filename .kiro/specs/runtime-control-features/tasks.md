# Implementation Plan: Runtime Control Features

This implementation plan adds runtime model switching and transport abstraction to achieve 100% feature parity with the Python SDK.

## Implementation Status

**Current State Analysis:**
- ✅ Client with Port-based communication exists
- ✅ Control Protocol with basic encoding/decoding exists
- ❌ No Model validation module
- ❌ No Transport behaviour or abstraction
- ❌ No set_model/get_model functionality
- ❌ No tests for new features

**Implementation Approach:**
Following Test-Driven Development (TDD) with Red-Green-Refactor cycles for quality and >95% coverage.

---

## Phase 1: Model Validation Module

### 1.1 Create Model test file with failing tests
- [x] Create `test/claude_agent_sdk/model_test.exs`



- [ ] Write test: `should_return_full_model_name_when_given_short_form_opus`
- [ ] Write test: `should_return_full_model_name_when_given_short_form_sonnet`
- [ ] Write test: `should_return_full_model_name_when_given_short_form_haiku`
- [ ] Write test: `should_return_same_name_when_given_full_form`
- [ ] Write test: `should_return_error_when_given_invalid_model`
- [ ] Write test: `should_return_error_when_given_nil`
- [ ] Write test: `should_return_error_when_given_empty_string`
- [ ] Run tests: `mix test test/claude_agent_sdk/model_test.exs` - verify all FAIL
- _Requirements: 2.1, 2.2, 2.3, 2.4, 7.1, 7.2, 7.10, 7.11_

### 1.2 Add tests for list_models/0
- [ ] Write test: `should_return_list_of_all_known_models`
- [ ] Write test: `should_include_both_short_and_full_forms`
- [ ] Write test: `should_return_sorted_list`
- [ ] Run tests - verify FAIL with "function undefined"
- _Requirements: 2.1, 7.1, 7.2_

### 1.3 Add tests for suggest/1
- [ ] Write test: `should_suggest_opus_when_given_opuss`
- [ ] Write test: `should_suggest_sonnet_when_given_sonet`
- [ ] Write test: `should_return_empty_when_no_similar_models`
- [ ] Write test: `should_return_top_3_suggestions_maximum`
- [ ] Run tests - verify FAIL with "function undefined"
- _Requirements: 2.4, 7.1, 7.2_

### 1.4 Implement Model module
- [ ] Create `lib/claude_agent_sdk/model.ex`
- [ ] Define @known_models map with short forms (opus, sonnet, haiku) and full forms
- [ ] Implement validate/1 returning {:ok, normalized_model} or {:error, :invalid_model}
- [ ] Implement list_models/0 returning sorted list of model names
- [ ] Implement suggest/1 using String.jaro_distance (>0.7 threshold, top 3)
- [ ] Add @moduledoc, @doc, and @spec to all functions
- [ ] Run tests - verify all PASS
- _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 7.3, 7.4, 8.1_

### 1.5 Verify Model coverage
- [ ] Run: `mix test --cover test/claude_agent_sdk/model_test.exs`
- [ ] Verify coverage >95% for Model module
- [ ] Add missing tests if needed
- _Requirements: 7.5, 7.12_


---

## Phase 2: Transport Behaviour Definition

### 2.1 Create Transport behaviour tests
- [ ] Create `test/claude_agent_sdk/transport_test.exs`
- [ ] Write test: `should_define_start_link_callback_with_arity_1`
- [ ] Write test: `should_define_send_callback_with_arity_2`
- [ ] Write test: `should_define_subscribe_callback_with_arity_2`
- [ ] Write test: `should_define_close_callback_with_arity_1`
- [ ] Write test: `should_define_status_callback_with_arity_1`
- [ ] Run tests - verify FAIL with "module not found"
- _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 7.1, 7.2_

### 2.2 Implement Transport behaviour
- [ ] Create `lib/claude_agent_sdk/transport.ex`
- [ ] Define @callback start_link(opts) :: {:ok, t()} | {:error, term()}
- [ ] Define @callback send(t(), message()) :: :ok | {:error, term()}
- [ ] Define @callback subscribe(t(), pid()) :: :ok
- [ ] Define @callback close(t()) :: :ok
- [ ] Define @callback status(t()) :: :connected | :disconnected | :error
- [ ] Define @type specifications (t, message, opts)
- [ ] Add @moduledoc with comprehensive documentation and custom transport guide
- [ ] Add @doc to all callbacks with examples
- [ ] Run tests - verify all PASS
- _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 7.4, 8.1, 8.2_

### 2.3 Verify Transport coverage
- [ ] Run: `mix test --cover test/claude_agent_sdk/transport_test.exs`
- [ ] Verify 100% coverage for behaviour definitions
- _Requirements: 7.5, 7.12_


---

## Phase 3: Port Transport Implementation

### 3.1 Create Port transport test file
- [ ] Create `test/claude_agent_sdk/transport/port_test.exs`
- [ ] Write tests for start_link/1: valid command, command not found, transport options
- [ ] Write tests for send/2: send when connected, error when not connected, binary messages
- [ ] Write tests for subscribe/2: register subscriber, send to subscribers, multiple subscribers
- [ ] Write tests for close/1: graceful close, wait for exit, timeout handling
- [ ] Write tests for status/1: connected, disconnected, error states
- [ ] Run tests - verify FAIL with "module not found"
- _Requirements: 3.2, 3.3, 3.5, 3.6, 7.1, 7.2, 7.3_

### 3.2 Implement Port transport module
- [ ] Create `lib/claude_agent_sdk/transport/port.ex`
- [ ] Add `use GenServer` and `@behaviour ClaudeAgentSDK.Transport`
- [ ] Define defstruct with fields: port, subscribers, buffer, options
- [ ] Extract Port.open logic from Client.start_cli_process into init/1
- [ ] Implement start_link/1 and init/1 with CLI command building
- [ ] Implement send/2 with Port.command and error handling
- [ ] Implement subscribe/2 with process monitoring
- [ ] Implement handle_info for Port messages {:data, {:eol, line}}
- [ ] Broadcast messages to subscribers as {:transport_message, message}
- [ ] Implement close/1 and terminate/2 with graceful shutdown (200ms timeout)
- [ ] Implement status/1 returning :connected | :disconnected | :error
- [ ] Add @moduledoc, @doc, and @spec to all functions
- [ ] Run tests - verify all PASS
- _Requirements: 3.2, 3.3, 3.5, 3.6, 3.9, 5.3, 5.4, 6.3, 7.4, 8.1_

### 3.3 Verify Port transport coverage
- [ ] Run: `mix test --cover test/claude_agent_sdk/transport/port_test.exs`
- [ ] Verify coverage >95% for Transport.Port module
- [ ] Add missing tests if needed
- _Requirements: 7.5, 7.12_

---

## Phase 4: Client Transport Integration

### 4.1 Add Client transport integration tests
- [ ] Open or create `test/claude_agent_sdk/client_test.exs`
- [ ] Write tests for transport integration: use Port by default, use custom transport, pass options
- [ ] Write tests for backward compatibility: work without transport option, show deprecation warning
- [ ] Write tests for transport message handling: subscribe to transport, handle disconnection
- [ ] Run tests - verify FAIL (transport field doesn't exist)
- _Requirements: 3.7, 3.8, 4.1, 4.2, 4.4, 5.1, 5.2, 5.3, 5.4, 5.5, 7.1, 7.2, 7.3_

### 4.2 Update Client state for transport
- [ ] Open `lib/claude_agent_sdk/client.ex`
- [ ] Add `transport: Transport.t() | nil` to state struct
- [ ] Add `transport_module: module()` to state struct
- [ ] Keep `port` field with deprecation comment
- _Requirements: 3.7, 5.1, 7.3_

### 4.3 Implement Client transport integration
- [ ] In init/1, check if transport option provided, default to Transport.Port
- [ ] Add deprecation warning if no transport specified
- [ ] In handle_continue(:start_cli), start transport instead of direct Port
- [ ] Call transport_module.start_link(transport_opts) and subscribe to messages
- [ ] Update handle_call({:send_message, _}) to use Transport.send instead of Port.command
- [ ] Update handle_info to process {:transport_message, msg} instead of Port messages
- [ ] Keep existing message parsing logic intact
- [ ] Handle transport disconnection events
- [ ] Update @moduledoc with transport examples
- [ ] Run tests - verify all PASS
- _Requirements: 3.7, 3.8, 4.1, 4.3, 4.4, 5.1, 5.2, 6.3, 6.4, 7.4, 8.1, 8.3_

### 4.4 Verify Client transport coverage
- [ ] Run: `mix test --cover test/claude_agent_sdk/client_test.exs`
- [ ] Verify coverage >95% for new transport integration code
- [ ] Add missing tests if needed
- _Requirements: 7.5, 7.12_


---

## Phase 5: Protocol Extensions for set_model

### 5.1 Add Protocol set_model tests
- [ ] Open or create `test/claude_agent_sdk/control_protocol/protocol_test.exs`
- [ ] Write tests for encode_set_model_request/1: return tuple, unique IDs, valid JSON, set_model subtype
- [ ] Write tests for decode_set_model_response/1: success response, extract model, error response, malformed
- [ ] Run tests - verify FAIL with "function undefined"
- _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 7.1, 7.2, 7.4_

### 5.2 Implement Protocol set_model functions
- [ ] Open `lib/claude_agent_sdk/control_protocol/protocol.ex`
- [ ] Implement encode_set_model_request/1 generating unique request_id
- [ ] Build control_request with type, request_id, and request (subtype: "set_model", model: name)
- [ ] Encode to JSON and return {request_id, json_string}
- [ ] Implement decode_set_model_response/1 pattern matching on response
- [ ] Extract model from success response or error message from error response
- [ ] Return {:ok, model} or {:error, reason}
- [ ] Add @doc and @spec to new functions
- [ ] Run tests - verify all PASS
- _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 7.4, 8.1_

### 5.3 Verify Protocol coverage
- [ ] Run: `mix test --cover test/claude_agent_sdk/control_protocol/protocol_test.exs`
- [ ] Verify coverage >95% for Protocol extensions
- [ ] Add missing tests if needed
- _Requirements: 7.5, 7.12_


---

## TDD Cycle 6: Client set_model/2 Implementation

### 🔴 RED Phase - Write Failing Tests

- [ ] 6.1 Add Client set_model tests
  - Open `test/claude_agent_sdk/client_test.exs`
  - Create MockTransport for testing (in test/support/)
  - Write describe block for "set_model/2"
  - Write setup block to start Client with MockTransport
  - Write test: `should_return_ok_when_model_change_succeeds`
  - Write test: `should_validate_model_before_sending_request`
  - Write test: `should_return_error_when_invalid_model`
  - Write test: `should_send_control_request_via_transport`
  - Write test: `should_update_current_model_after_success`
  - Write test: `should_timeout_after_30_seconds`
  - Write test: `should_return_error_when_model_change_in_progress`
  - Run tests: **Verify tests FAIL** with "function undefined"
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 6.1, 7.1, 7.2, 7.7_

- [ ] 6.2 Add Client get_model tests
  - Write describe block for "get_model/1"
  - Write test: `should_return_current_model_when_set`
  - Write test: `should_return_initial_model_from_options`
  - Write test: `should_return_updated_model_after_set_model`
  - Write test: `should_return_error_when_no_model_set`
  - Run tests: **Verify tests FAIL** with "function undefined"
  - _Requirements: 1.8, 7.1, 7.2, 7.7_

### ✅ GREEN Phase - Implement Minimal Code

- [ ] 6.3 Add model tracking to Client state
  - Add `current_model: String.t() | nil` to state struct
  - Add `pending_model_change: {GenServer.from(), reference()} | nil`
  - Initialize current_model from Options.model in init/1
  - Run tests: **Verify tests still FAIL** but state is updated
  - _Requirements: 1.3, 7.3_

- [ ] 6.4 Implement set_model/2 public function
  - Add @spec and @doc for set_model/2
  - Validate model using Model.validate/1
  - Return {:error, :invalid_model} if validation fails
  - Call GenServer.call(client, {:set_model, model}, 30_000)
  - Run tests: **Verify validation tests PASS**
  - _Requirements: 1.1, 1.6, 6.1, 7.4_

- [ ] 6.5 Implement handle_call for set_model
  - Add handle_call({:set_model, model}, from, state)
  - Check if pending_model_change is nil
  - Return {:error, :model_change_in_progress} if not nil
  - Encode set_model request using Protocol
  - Send request via Transport.send
  - Store {from, make_ref()} in pending_model_change
  - Schedule timeout message after 30 seconds
  - Return {:noreply, state}
  - Run tests: **Verify request sending tests PASS**
  - _Requirements: 1.2, 6.1, 7.4_


- [ ] 6.6 Handle set_model control response
  - Add pattern in handle_decoded_message for set_model response
  - Decode response using Protocol.decode_set_model_response
  - If success, update current_model in state
  - Reply to pending caller with :ok
  - Clear pending_model_change
  - Cancel timeout
  - Log success at info level
  - Run tests: **Verify success handling tests PASS**
  - _Requirements: 1.3, 1.4, 11.2, 7.4_

- [ ] 6.7 Handle set_model errors
  - Pattern match error responses
  - Reply to pending caller with {:error, reason}
  - Clear pending_model_change
  - Cancel timeout
  - Log error at error level
  - Run tests: **Verify error handling tests PASS**
  - _Requirements: 1.5, 6.2, 6.3, 11.3, 7.4_

- [ ] 6.8 Handle set_model timeout
  - Add handle_info for timeout message
  - Check if timeout is for current pending request
  - Reply with {:error, :timeout}
  - Clear pending_model_change
  - Log timeout at error level
  - Run tests: **Verify timeout tests PASS**
  - _Requirements: 6.1, 7.4_

- [ ] 6.9 Implement get_model/1
  - Add @spec and @doc for get_model/1
  - Add handle_call(:get_model, _from, state)
  - Return {:ok, current_model} or {:error, :no_model_set}
  - Run tests: **Verify get_model tests PASS**
  - _Requirements: 1.8, 7.4_

### ♻️ REFACTOR Phase - Improve Code Quality

- [ ] 6.10 Refactor Client model switching
  - Extract model validation to private function
  - Extract timeout scheduling to private function
  - Extract response handling to private functions
  - Update @moduledoc with model switching examples
  - Add comprehensive @doc to set_model/2 and get_model/1
  - Add @spec type specifications
  - Run tests: **Verify all tests still PASS**
  - _Requirements: 7.4, 8.1, 8.3_

### 📊 COVERAGE Phase - Verify Coverage

- [ ] 6.11 Measure and verify coverage
  - Run: `mix test --cover test/claude_agent_sdk/client_test.exs`
  - Check coverage for Client model switching code
  - **Verify coverage >95%** for new code
  - If <95%, add missing test cases and repeat GREEN phase
  - _Requirements: 7.5, 7.12_


---

## TDD Cycle 7: Integration Testing

### 🔴 RED Phase - Write Failing Integration Tests

- [ ] 7.1 Create model switching integration test
  - Create `test/integration/model_switching_live_test.exs`
  - Add @moduletag :live
  - Write test: `should_preserve_context_when_switching_models`
  - Start Client with sonnet
  - Send initial message
  - Switch to opus
  - Send follow-up message
  - Verify context preserved
  - Run test: **Verify test FAILS** (may need CLI support)
  - _Requirements: 1.7, 7.4, 7.9_

- [ ] 7.2 Create custom transport integration test
  - Create `test/integration/custom_transport_test.exs`
  - Create MockTransport in test/support/
  - Write test: `should_work_with_custom_transport`
  - Start Client with MockTransport
  - Send messages
  - Verify message flow
  - Run test: **Verify test FAILS** initially
  - _Requirements: 4.1, 4.2, 7.4, 7.9_

- [ ] 7.3 Create backward compatibility test
  - Create `test/integration/backward_compat_test.exs`
  - Write test: `should_work_without_transport_option`
  - Start Client without transport (should use Port)
  - Verify all existing functionality works
  - Verify deprecation warning shown
  - Run test: **Verify test FAILS** initially
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 7.4, 7.9_

### ✅ GREEN Phase - Make Integration Tests Pass

- [ ] 7.4 Fix integration test failures
  - Debug any failures in integration tests
  - Ensure all components work together
  - Fix any integration issues discovered
  - Run tests: **Verify all integration tests PASS**
  - _Requirements: 7.4, 7.9_

### ♻️ REFACTOR Phase - Improve Integration Tests

- [ ] 7.5 Refactor integration tests
  - Extract common setup to shared helpers
  - Improve test assertions
  - Add better error messages
  - Run tests: **Verify all tests still PASS**
  - _Requirements: 7.4_

### 📊 COVERAGE Phase - Overall Coverage Check

- [ ] 7.6 Measure overall coverage
  - Run: `mix test --cover`
  - Check overall coverage for all new code
  - **Verify overall coverage >95%**
  - If <95%, identify gaps and add tests
  - _Requirements: 7.5, 7.12_


---

## Phase 8: Documentation (Post-TDD)

- [ ] 8.1 Create Runtime Control Guide
  - Create `docs/RUNTIME_CONTROL.md`
  - Explain when to use runtime model switching
  - Document performance implications
  - Provide best practices
  - Include code examples
  - _Requirements: 8.1_

- [ ] 8.2 Create Custom Transport Guide
  - Create `docs/CUSTOM_TRANSPORTS.md`
  - Step-by-step guide for implementing custom transport
  - Testing strategies
  - Example: HTTP-based transport
  - _Requirements: 8.2_

- [ ] 8.3 Create Migration Guide
  - Create `docs/MIGRATION_V0_5.md`
  - Document changes from v0.4.0 to v0.5.0
  - Deprecation timeline
  - Code migration examples
  - _Requirements: 8.1_

- [ ] 8.4 Update README.md
  - Add "Runtime Control" section
  - Add "Custom Transports" section
  - Update feature list
  - Update implementation status
  - _Requirements: 8.3_

- [ ] 8.5 Update PYTHON_SDK_COMPARISON.md
  - Change "Runtime Model Switching" to ✅
  - Change "Transport Abstraction" to ✅
  - Update completeness score to 100%
  - Update conclusion
  - Add comparison examples
  - _Requirements: 8.4_

- [ ] 8.6 Update CRITICAL_ASSESSMENT_COMPARISON.md
  - Update "What's Actually Missing" section
  - Update feature parity matrix
  - Update completeness score
  - Add "Completed in v0.5.0" section
  - _Requirements: 8.4_

---

## Phase 9: Code Quality and Release

- [ ] 9.1 Run dialyzer
  - Fix all type warnings
  - Ensure all @spec declarations correct
  - Add missing type specifications
  - _Requirements: 5.5_

- [ ] 9.2 Run credo
  - Fix all code style issues
  - Ensure consistent formatting
  - Add missing documentation
  - _Requirements: 5.5_

- [ ] 9.3 Run full test suite
  - Run: `mix test`
  - Ensure all tests pass
  - Verify no flaky tests
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.9_

- [ ] 9.4 Manual testing with real CLI
  - Test with real Claude CLI (not mock)
  - Verify model switching works end-to-end
  - Test error scenarios
  - Verify performance targets met
  - _Requirements: 7.8, 10.1, 10.2, 10.3, 10.4, 10.5_

- [ ] 9.5 Update CHANGELOG.md
  - Add v0.5.0 section
  - List all new features
  - List deprecations
  - Include migration notes

- [ ] 9.6 Update version numbers
  - Update version in mix.exs to 0.5.0
  - Update version in README badges
  - Update installation instructions

- [ ] 9.7 Create release notes
  - Summarize new features
  - Highlight breaking changes (none expected)
  - Include upgrade instructions
  - Link to documentation

---

## Summary

**TDD Cycles**: 7 major cycles
**Total Tasks**: 9 phases, 100+ sub-tasks
**All tasks are REQUIRED** (TDD approach requires comprehensive testing)

**Estimated Timeline**: 7-10 days
- TDD Cycle 1 (Model): 0.5 days
- TDD Cycle 2 (Transport Behaviour): 0.5 days
- TDD Cycle 3 (Port Transport): 2 days
- TDD Cycle 4 (Client Integration): 1.5 days
- TDD Cycle 5 (Protocol): 0.5 days
- TDD Cycle 6 (set_model): 1.5 days
- TDD Cycle 7 (Integration): 1 day
- Phase 8 (Documentation): 1 day
- Phase 9 (Quality & Release): 0.5 days

**Success Criteria**:
- ✅ All tests written before implementation
- ✅ All tests pass (Red → Green → Refactor)
- ✅ Coverage >95% for all new code
- ✅ All 60+ acceptance criteria met
- ✅ No breaking changes
- ✅ 100% feature parity with Python SDK

**TDD Benefits**:
- Higher code quality from the start
- Better test coverage (>95% guaranteed)
- Fewer bugs in production
- Easier refactoring
- Living documentation through tests
