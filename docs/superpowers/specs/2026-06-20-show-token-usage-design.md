# Design: `detdoc run --show-token-usage`

## Goal

Add an opt-in `--show-token-usage` flag to `detdoc run` so users can see how many tokens a run consumed. The flag applies only to `run`; `apply` remains unchanged because saved-run apply does not call pi.

## User interface

`detdoc run --show-token-usage` behaves like today, then prints a final token usage summary after the run result. Without the flag, output remains unchanged.

Example:

```txt
Run 20260620-123456 saved
Token usage:
  plan: input 12,345, output 678, cache read 0, cache write 0, total 13,023
  implement: input 45,000, output 2,100, cache read 8,000, cache write 0, total 55,100
  total: input 57,345, output 2,778, cache read 8,000, cache write 0, total 68,123
```

If the active agent does not report usage, DetDoc should print a clear zero/empty summary rather than failing.

## Architecture

Introduce a small token-usage type in the agent layer and let agent methods optionally return usage metadata:

- `plan` returns the proposed plan plus usage;
- `implement` returns usage;
- `repairValidation` returns usage.

The flow aggregates usage by phase and includes it in `FlowResult`. The CLI prints it only when `--show-token-usage` is passed.

## Data flow

1. `run` parses `--show-token-usage`.
2. `PiSdkRunner` reads usage from assistant messages after each `session.prompt(...)`.
3. `runFlow` records usage for `plan`, `implement`, and each validation repair attempt.
4. `run` prints the normal result line, then prints token usage summary when requested.

## Error handling

Missing usage fields are treated as zero. Token usage reporting must not change run success/failure semantics.

## Testing

Add tests for:

- `run --help` documents `--show-token-usage`;
- `run --show-token-usage` with the fake agent prints a token usage section;
- running without the flag does not print token usage.
