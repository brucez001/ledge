# Security Policy

## Supported versions

Ledge is currently distributed as source code rather than as signed release
downloads. Security fixes are made against the latest version of the `main`
branch.

## Reporting a vulnerability

Please do not report suspected security vulnerabilities in a public issue.
Instead, use GitHub's private vulnerability reporting:

1. open the repository's **Security** tab;
2. select **Advisories**; and
3. choose **Report a vulnerability**.

Include the affected commit or version, macOS version, impact, reproduction
steps, and any suggested remediation. Reports should avoid including real
credentials, cookies, personal data, or other sensitive information.

I aim to acknowledge a report within seven days. Details should remain private
until the issue has been assessed and a fix or disclosure plan is available.

## Scope

Security reports may cover Ledge's source code, build scripts, local data
handling, WebKit integration, permissions, and window or keyboard behaviour.

Vulnerabilities in websites opened through Ledge are outside this project's
scope. Issues in WebKit or macOS itself should also be reported to Apple through
its security reporting process.
