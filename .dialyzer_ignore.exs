[
  # Ignore warnings about external dependencies
  {:warn_unmatched_returns, :_, {:_, :erlexec, :_}},
  # Mix.Task behaviour callbacks are not included in dialyzer PLT by default
  # These warnings can be safely ignored as the Mix task works correctly
  {"lib/mix/tasks/test.live.ex", :callback_info_missing},
  {"lib/mix/tasks/test.live.ex", :unknown_function}
]