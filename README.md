# DetDoc

DetDoc turns Markdown documentation changes or explicit bugfix intent into approved, validated, replayable code patches using embedded pi.

## Commands

```bash
detdoc init
detdoc diff
detdoc plan
detdoc run
detdoc fix "message to fix"
detdoc apply <run-id>
detdoc replay <run-id>
```

## Workflow

1. Edit Markdown documentation.
2. Run `detdoc run`.
3. Approve the structured plan.
4. Review the generated patch.
5. Type `approve` to apply the patch.

For bug fixes that should not require a documentation edit, run:

```bash
detdoc fix "describe the bug and expected behavior"
```

## Reproducibility

DetDoc stores each run under `.detdoc/runs/<run-id>/`. The stored `changes.patch` can be applied again with:

```bash
detdoc replay <run-id>
```

Replay checks the recorded base commit and preimage file hashes before applying the patch.

## Configuration

Project config lives at `.detdoc/config.yml`.

```yaml
docs:
  include:
    - "**/*.md"
  exclude:
    - ".detdoc/**"
    - "node_modules/**"

paths:
  deny:
    - ".env"
    - ".env.*"
    - "node_modules/**"
    - ".git/**"

validation:
  commands: []

agent:
  provider: pi-sdk
  model: null
  thinking: high

worktree:
  keepOnFailure: true
```

## Development

```bash
npm install
npm test
npm run typecheck
npm run build
```

The built CLI entrypoint is `dist/src/index.js`.
