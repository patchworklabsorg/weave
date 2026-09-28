# Security Policy

Weave is the identity provider and OAuth 2.0 server for Patchwork Labs. A flaw in Weave can give access to every app that signs in through it. Please report security problems privately.

## Supported versions

Only the `main` branch is supported. It is what runs in production. Fixes are not backported.

## Report a vulnerability

Do not open a public issue or pull request for a security problem.

1. Go to the [Security tab](https://github.com/patchworklabsorg/weave/security) of this repository.
2. Click **Report a vulnerability**.
3. Describe the problem, the affected code, and the steps to reproduce it.

A patch or a failing test is welcome. Attach it to the report, not to a public pull request.

## What to expect

- We confirm that we received the report.
- We tell you if we accept the report and how we plan to fix it.
- We fix accepted reports on a private branch, deploy the fix, and then publish a security advisory.
- We credit you in the advisory, unless you ask us not to.

## Scope

In scope:

- Authentication and sessions: magic links, passwords, impersonation, session revocation.
- OAuth 2.0 and OpenID Connect: `/oauth/*` endpoints, tokens, consent, redirect URI checks.
- Authorization in the admin panel and in the engines under `/admin`.
- Webhook endpoints, for example `/webhooks/slack/*`.
- The API under `/api`.

Out of scope:

- Denial of service and volume-based attacks.
- Reports from automated scanners without a working proof of concept.
- Social engineering of Patchwork Labs staff or members.
- Problems in third-party services, for example Slack or GitHub. Report these to the vendor.

## Safe testing

- Test only against a local copy of Weave. Do not test against production.
- Do not access, change or delete data that is not yours.
- If you find user data by accident, stop and tell us in your report.
