---
name: pr-screenshots
description: Screenshots of the pages a branch changes, light and dark, desktop and 390px, added to the PR body. Use before `gh pr create` or when a PR needs screenshots; a hook blocks `gh pr create` on a branch that changes views until this has run.
---

# PR screenshots

Every Weave PR that changes what a person sees shows it: each changed page in light and dark, at 1280px and 390px, in the PR body. The pass is also a check. It runs the real pages with Bullet on, so it finds N+1 queries, 500s and phone overflow that request specs miss.

All scripts are in `.claude/skills/pr-screenshots/scripts/`. Run them from the repo root. `<db>` is `weave_shots_<short branch name>`, `<shots>` is a folder in your scratchpad.

## Steps

1. **List the pages.** Read `git diff origin/main...HEAD --stat` and the changed views. Write down each page and each state a reviewer needs to see: empty, filled, after the main action (for example "request sent", "approved"), and every role that sees a different page (member, manager, admin). Done when every changed view and every new state is on the list.

2. **Prepare.** Run `scripts/prepare.sh <db>`. It makes a private database (the shared dev and test databases belong to other sessions) and builds the CSS and JS.

3. **Seed.** Write a seed script in your scratchpad that creates the demo data for the list. Start it with `require_relative` of `scripts/seed_helpers.rb`, and use names and `example.com` addresses, never real people. Run it with `DATABASE_URL=postgres://localhost/<db> RAILS_ENV=test bin/rails runner <seed>`.

4. **Serve.** Start `scripts/serve.sh <db>` in the background and wait until `curl http://127.0.0.1:3077/up` answers 200. The test env does not reload code: restart the server after every edit.

5. **Sign in links.** Run `EMAILS=<viewer emails> DATABASE_URL=... RAILS_ENV=test bin/rails runner scripts/sign_in_links.rb`. Each link works once, so print new links before every run.

6. **Shoot.** Copy `scripts/shoot.template.js` to `.playwright-mcp/shoot.js`, fill in `CONFIG` (viewers, tokens, shots, the `<shots>` path), and run it with the Playwright MCP tool `browser_run_code_unsafe` and `filename`. For a state that needs an action (submit a form, approve), add the steps in the routine after the sign-in. A Turbo confirm opens a dialog: accept it with `page.once('dialog', (d) => d.accept())` before the click.

7. **Look.** Open every image with the Read tool. Check against `docs/UI.md`: token colors in both themes, padding inside cards, one `btn-primary`, nothing cut off or squeezed at 390px. The result lines also flag a non-200 status and any element wider than the viewport. Fix what the change caused, add a spec when the fix is a code bug (an N+1 gets a spec with two or more rows), restart the server and shoot again. Done when every image is clean, or the only problem is in code this branch did not touch: then note it for the PR body.

8. **Upload.** Run `scripts/upload.sh pr-<number> <shots>`. It adds the images to the `pr-screenshots` branch through the GitHub API, without local git, and prints the base URL. Before the PR exists, use the branch name as the folder.

9. **Add to the PR body.** Add a `## Screenshots` section: one heading per page or state, one sentence on what it shows, and a table with Light, Dark and 390px columns. Use `![](<base>/<file>)` for desktop and `<img src="<base>/<file>" width="200">` for 390px. Say that the images are on the `pr-screenshots` branch.

10. **Record.** Write the marker that the hook reads:

    ```
    d="$(git rev-parse --path-format=absolute --git-common-dir)/pr-screenshots"
    b="$(git branch --show-current)"
    mkdir -p "$d" && git rev-parse HEAD > "$d/${b//\//__}"
    ```

    If the user said to skip screenshots, write `skipped` to the same file instead.

11. **Clean up.** Stop the server (`kill $(cat tmp/pids/screenshots-3077.pid)`).
