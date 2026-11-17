# Security policy

## Supported versions

{{DISTRIBUTION}} Security fixes are developed on `main` and reach users in the next release, so keep {{PROJECT_NAME}} updated. There is no commitment to backport a fix to an earlier version.

## Report a vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/{{OWNER}}/{{REPO}}/security/advisories/new) to contact the maintainers without publishing exploit details. Include the {{PROJECT_NAME}} version, your environment, a minimal reproduction, impact, and any proposed mitigation. Do not put secrets or private source code in reports.

If the private reporting form is unavailable, use the contact options on the [maintainer's GitHub profile](https://github.com/{{MAINTAINER}}) to arrange a private report. Do not open a public issue containing an unpatched exploit.

## Runtime model

{{RUNTIME_MODEL}}

CI uses CodeQL, dependency review, a production dependency audit, Socket dependency scanning, and OpenSSF Scorecard. Socket requires a configured API token and skips fork PRs. These checks help identify problems; they do not establish that the project is vulnerability-free.
