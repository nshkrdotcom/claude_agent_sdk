# Bare Exception Blocks Silently Swallow Errors

- **What's missing:** Several locations use bare `except Exception:` or `except:` blocks that silently discard errors, making debugging difficult and potentially hiding important failures.

- **Evidence:**

  1. **stderr handling** - `src/claude_agent_sdk/_internal/transport/subprocess_cli.py:396-399`:
     ```python
     except anyio.ClosedResourceError:
         pass  # Stream closed, exit normally
     except Exception:
         pass  # Ignore other errors during stderr reading
     ```
     Any exception during stderr reading is silently ignored.

  2. **Process wait** - `src/claude_agent_sdk/_internal/transport/subprocess_cli.py:543-546`:
     ```python
     try:
         returncode = await self._process.wait()
     except Exception:
         returncode = -1
     ```
     Exceptions during process wait are converted to `-1` without logging or context.

  3. **Version check** - `src/claude_agent_sdk/_internal/transport/subprocess_cli.py:586-589`:
     ```python
     except Exception:
         pass
     ```
     Entire version check block silently fails on any exception.

- **Impact:**
  1. Silent failures make debugging difficult ("why isn't my code working?")
  2. Important errors (e.g., permission denied, network issues) are hidden
  3. Users may not realize something is wrong until much later
  4. No visibility into what went wrong or how to fix it
  5. Violates Python best practice of explicit error handling

- **Proposed fix:**
  1. Replace bare `except Exception:` with specific exception types where possible
  2. Add logging at DEBUG or WARNING level for silently handled exceptions:
     ```python
     except Exception as e:
         logger.debug(f"Ignoring error during stderr reading: {e}")
     ```
  3. For the version check, log a warning so users know why version check was skipped:
     ```python
     except Exception as e:
         logger.warning(f"Could not check Claude version: {e}")
     ```
  4. Consider whether some of these should actually raise or be handled differently
  5. Add documentation explaining which errors are intentionally suppressed and why
