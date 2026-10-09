# Code of Conduct acceptance

Every Slack member accepts the Patchwork Labs Code of Conduct. New members accept it when they join (see `User#slack_onboarding_step`). This page is about members who joined before that step existed.

## The flow

```mermaid
flowchart TD
  A[Full member, no acceptance] -->|slack:coc:request| B[Slack DM + email]
  B -->|DM button or /slack| C[Accepted]
  B -->|no answer by the deadline| D[slack:coc:demote]
  D --> E[Single-channel guest in the CoC channel, DM + email]
  E -->|DM button or /slack| F[Accepted, promoted to full member]
```

- The DM button accepts at once. When the Slack import saved a placeholder name (`NOTSET`, `Unknown`, `User`), the button opens a Slack form that also asks for the name.
- The email links to sign-in. After sign-in, `/` sends the member to `/slack`, which shows the same accept step and name fields.
- The message text is in `config/locales/code_of_conduct_request.en.yml`.

## Runbook

Run these in the production container.

1. Count the members: `bin/rails slack:coc:status`.
2. Preview the message: `bin/rails slack:coc:request DEADLINE=2026-11-01`.
3. Send it: `bin/rails slack:coc:request SEND=1 DEADLINE=2026-11-01`.
4. Optional: send a reminder: `bin/rails slack:coc:request SEND=1 REMIND=1 DEADLINE=2026-11-01`.
5. After the deadline, preview the demotions: `bin/rails slack:coc:demote ASKED_BEFORE=2026-10-15`.
6. Demote: `bin/rails slack:coc:demote CONFIRM=1 ASKED_BEFORE=2026-10-15`. Slack admins and owners are skipped.

## App access

When the Flipper flag `require_code_of_conduct` is on, a user who has not accepted cannot use any OAuth app (see `AppAccess`). The authorize endpoint sends them to `/slack` to accept and then back to the app. Their existing tokens stop working until they accept. The flag is off while it does not exist.
