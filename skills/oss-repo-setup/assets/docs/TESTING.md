# Testing

Tests must prove observable behavior, including failure paths. Source coverage is a useful signal, not proof that every integration works.

## Commands

```sh
pnpm test              # Vitest
pnpm test:coverage     # Same run with V8 coverage (coverage/lcov.info, coverage/coverage-final.json)
pnpm check             # Complete local gate
```

## Test layers

{{TEST_LAYERS}}

CI runs the suite on Linux, Windows and macOS. Codecov receives one Linux report to avoid duplicate uploads. The upload passes the organization `CODECOV_TOKEN` and sets `fail_ci_if_error`; a fork PR cannot read that secret.

## Manual verification

{{MANUAL_VERIFICATION}}

## Regression expectations

Use `test`, observable names, literal expected values, and Arrange/Act/Assert. Assert what a user would notice rather than private fields. Await asynchronous work and dispose what the test creates.
