# Security Policy

## Supported Versions

Security fixes are provided for the latest released version.

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.
Use GitHub private vulnerability reporting when available. If unavailable,
contact the maintainer and state that the report is security-sensitive.

Include:

- affected version or commit
- reproduction steps or proof of concept
- expected impact
- whether credentials, CI/CD, release artifacts, filesystem access, or network access are involved

## Response Targets

- Initial acknowledgement: within 7 days
- Triage update: within 14 days when reproduction details are sufficient
- Coordinated disclosure: after a fix is available, or earlier if public risk requires it

## Scope

In scope:

- CI/CD, dependency, and GitHub Actions supply-chain risks
- release artifact integrity issues
- credential exposure
- privilege boundary bypasses relevant to this project

Out of scope:

- social engineering against maintainers or users
- vulnerabilities in third-party services not controlled by this repo
