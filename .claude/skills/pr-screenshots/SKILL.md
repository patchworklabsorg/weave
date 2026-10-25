---
name: pr-screenshots
description: Screenshots of the pages a branch changes, light and dark, desktop and 390px, added to the PR body. Use before `gh pr create` or when a PR needs screenshots; a hook blocks `gh pr create` on a branch that changes views until this has run.
---

# PR screenshots

Every Weave PR that changes what a person sees shows it: each changed page in light and dark, at 1280px and 390px, in the PR body. The pass is also a check. It runs the real pages with Bullet on, so it finds N+1 queries, 500s and phone overflow that request specs miss.

Run every command from the repo root. `S` below is `.claude/skills/pr-screenshots/scripts`. `<shots>` is a new, empty folder in your scratchpad: only the images of this run go in it, because step 8 publishes the folder.

## Steps

1. **List the pages.** Read `git diff origin/main...HEAD --stat` and the changed views and locale files. Write down each page and each state a reviewer needs to see: empty, filled, after the main action (for example "request sent", "approved"), and every role that sees a different page (member, manager, admin). Done when every changed view and every new state is on the list. Email templates are out of scope.

2. **Prepare.** Run `S/prepare.sh`. It prints `<db>`, a private database named after this worktree (the shared dev and test databases belong to other sessions), and builds the CSS and JS. If the drop fails, a server from an earlier run is still connected: stop it (step 11) and run it again.

3. **Seed.** Write a seed script in your scratchpad that creates the demo data for the list. Start it with `require_relative "<absolute repo path>/.claude/skills/pr-screenshots/scripts/seed_helpers"`, and use made-up names and `example.com` addresses. Run it with `DATABASE_URL=postgres://localhost/<db> RAILS_ENV=test bin/rails runner <seed>`.

4. **Serve.** Start `S/serve.sh <db>` in the background and wait until `curl http://127.0.0.1:3077/up` answers 200. The test env does not reload code: run `S/serve.sh <db>` again after every edit, and it replaces the old server.

5. **Sign-in links.** Run `EMAILS=<viewer emails> DATABASE_URL=postgres://localhost/<db> RAILS_ENV=test bin/rails runner .claude/skills/pr-screenshots/scripts/sign_in_links.rb`. Each link works once, so print new links before every run.

6. **Shoot.** Copy `S/shoot.template.js` to `.playwright-mcp/shoot.js`, fill in `CONFIG` (viewers, tokens, shots, `out: <shots>`), and run it with the Playwright MCP tool `browser_run_code_unsafe` and `filename`. For a state that needs an action (submit a form, approve), add the steps in the routine after the sign-in. A Turbo confirm opens a dialog: call `page.once('dialog', (d) => d.accept())` before the click. Keep the file names `<n>-<state>-<light|dark>-<width>.png`: the upload takes only those.

7. **Look.** Open every image with the Read tool. Check against `docs/UI.md`: token colors in both themes, padding inside cards, one `btn-primary`, nothing cut off or squeezed at 390px. The result lines also flag a non-200 status and any element wider than the viewport. Fix what the change caused, add a spec when the fix is a code bug (an N+1 gets a spec with two or more rows), restart the server and shoot again. Done when every image is clean, or the only problem is in code this branch did not touch: then note it for the PR body.

8. **Upload.** The repo is public and the links are permanent, so check that `<shots>` holds only this run's demo-data images. Then run `S/upload.sh pr-<number> <shots>`. It lists the files, adds them to the `pr-screenshots` branch through the GitHub API (no local git), and prints the base URL. Before the PR exists, use the branch name with `/` replaced by `-` as the folder.

9. **Add to the PR body.** Add a `## Screenshots` section: one heading per page or state, one sentence on what it shows, and a table with Light, Dark and 390px columns. Use `![](<base>/<file>)` for desktop and `<img src="<base>/<file>" width="200">` for 390px. Say that the images are on the `pr-screenshots` branch.

10. **Record.** Write the marker that the hook reads. It holds the commit you screenshotted, so a later UI change asks for new screenshots:

    ```
    d="$(git rev-parse --path-format=absolute --git-common-dir)/pr-screenshots"
    b="$(git branch --show-current)"
    mkdir -p "$d" && git rev-parse HEAD > "$d/${b//\//__}"
    ```

    If the user said to skip screenshots, write `skipped` to the same file instead.

11. **Clean up.** Stop the server: `kill "$(cat tmp/pids/screenshots-3077.pid)"` (use the port you passed to `serve.sh`).
