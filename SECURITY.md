# Security Policy

## Supported versions

Ledge is currently distributed as source code rather than as signed release
downloads. Security fixes are made against the latest version of the `main`
branch.

## Reporting a vulnerability

Please do not report suspected security vulnerabilities in a public issue.

Use GitHub's private vulnerability reporting: open the repository's
**Security** tab and choose **Report a vulnerability**. Include the affected
commit, macOS version, impact, and reproduction steps, and avoid including real
credentials, cookies, personal data, or other sensitive information.

If the private reporting form is unavailable, open a minimal public issue that
says only "security report — please provide a private contact". Do not include
technical details; a private channel will be arranged from there.

Reports are acknowledged within seven days. Details should remain private until
the issue has been assessed and a fix or disclosure plan is available.

## Scope

Security reports may cover Ledge's source code, build scripts, local data
handling, WebKit integration, permissions, and window or keyboard behaviour.

Vulnerabilities in websites opened through Ledge are outside this project's
scope. Issues in WebKit or macOS itself should also be reported to Apple through
its security reporting process.
