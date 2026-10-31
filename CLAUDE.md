# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Patchwork Labs Identity Provider (IDP) - An OAuth 2.0 authorization server and identity management system built with Rails 8.0. This application provides user authentication, authorization, profile management, and OAuth 2.0 provider capabilities for the Patchwork Labs ecosystem.

## Development Commands

### Running the Application
```bash
bin/dev                          # Start all services (web, CSS watch, JS watch via Procfile.dev)
bin/rails server                 # Rails server only
bin/rails console                # Interactive console
```

### Testing
```bash
bin/rails test                   # Run Minitest suite
rspec                            # Run RSpec suite (both frameworks coexist)
bin/rails test test/models/user_test.rb  # Single test file
```

### Code Quality
```bash
bin/rubocop                      # Lint Ruby code (Rails Omakase + custom rules)
bin/rubocop -A                   # Auto-fix safe offenses
bin/brakeman --no-pager         # Security vulnerability scan
bin/rails zeitwerk:check         # Verify autoloading configuration
```

### Database
```bash
bin/rails db:migrate             # Run pending migrations
bin/rails db:rollback            # Rollback last migration
bundle exec annotaterb models    # Update model schema annotations (run after migrations)
```

### Assets
```bash
bun install                      # Install JavaScript dependencies
bun run build                    # Build JavaScript (Rollup via bun)
bin/rails tailwindcss:build      # Build Tailwind CSS
bin/rails tailwindcss:watch      # Watch and rebuild CSS
bin/rails assets:precompile      # Production asset compilation
```

### Admin Tools (Development)
- Flipper (Feature Flags): http://localhost:3000/flipper
- Blazer (BI Dashboard): http://localhost:3000/blazer
- Mission Control (Jobs): http://localhost:3000/admin/jobs
- Letter Opener (Email Preview): http://localhost:3000/letter_opener

## Architecture

### OAuth 2.0 Provider
This application is a complete OAuth 2.0 authorization server built on Doorkeeper. Key endpoints:

- Authorization: `GET /oauth/authorize` - Authorization code flow entry point
- Token Exchange: `POST /oauth/token` - Exchange authorization codes for access tokens
- UserInfo: `GET /oauth/userinfo` - RFC 7662 user information endpoint
- Introspection: `POST /oauth/introspect` - Token introspection
- Revocation: `POST /oauth/revoke` - Revoke access/refresh tokens
- Discovery: `GET /.well-known/oauth-authorization-server` - RFC 8414 metadata

Supported flows: Authorization Code with PKCE, Client Credentials, Refresh Token

### Controller Organization
- **Public Routes**: `auth_controller.rb`, `users_controller.rb`, `home_controller.rb`
- **Admin Namespace** (`app/controllers/admin/`): User management, OAuth app management, services, webhooks
- **API Namespace** (`app/controllers/api/`): Programmatic access endpoints
- **OAuth** (`app/controllers/oauth/`): Custom OAuth extensions (userinfo, etc.)
- **Webhooks** (`app/controllers/webhooks/`): Service webhook receivers

### Service Pattern
Business logic lives in service objects (`app/services/`), not controllers or models. Controllers should be thin, delegating complex operations to services.

Example: `SlackService` handles Slack API interactions, `SyncUserToSlackJob` orchestrates profile sync workflow.

### Model Serializers
**Always create serializers for models exposed via API** (`app/serializers/`). Use Jbuilder for JSON API responses. Never return raw ActiveRecord objects from API endpoints.

### Public ID System
Uses `encoded_ids` gem for Stripe-style public IDs (e.g., `user_01HQXYZ...`). All public-facing IDs use this format instead of database primary keys.

Access via:
- `user.pd_id` - Returns encoded public ID
- `User.find_by_pd_id(id)` - Find by public ID

### Soft Deletions
Models use `acts_as_paranoid` for soft deletion. Records are never hard-deleted; they're marked with `deleted_at` timestamp.

- Default scopes automatically exclude soft-deleted records
- Use `.with_deleted` to include soft-deleted records
- Use `.only_deleted` to query only soft-deleted records

### Background Jobs
Uses Solid Queue (database-backed Active Job adapter). Jobs live in `app/jobs/`.

- Keep jobs idempotent
- Handle failures gracefully with retries
- Monitor via Mission Control at `/admin/jobs`

### Webhooks System
Services can register webhooks for events (user created, updated, etc.). Webhook deliveries are tracked in `webhook_deliveries` table with retry logic.

Admin can manage webhooks at `/admin/services/:id/webhooks`.

### Database Migrations
Uses `strong_migrations` gem to catch dangerous migration patterns. If a migration is flagged:
- Read the error message carefully
- Follow the suggested safe alternative
- Never disable safety checks without understanding the risk

After migrations, always run: `bundle exec annotaterb models`

### Security Considerations
- All user passwords use BCrypt hashing
- Sensitive data encrypted with Lockbox
- Rate limiting via Rack::Attack (configured in `config/initializers/rack_attack.rb`)
- OAuth redirect URIs are strictly validated

### Feature Flags
Use Flipper for feature rollouts. Check flags with:
```ruby
if Flipper.enabled?(:feature_name, current_user)
  # New feature code
end
```

Manage flags at `/flipper` in development.

## Key Conventions

### Routing
RESTful routes are strongly preferred. Nested resources follow Rails conventions:
```ruby
resources :services do
  resources :keys, controller: "service_keys"
  resources :webhooks, controller: "service_webhooks"
end
```

### Model Concerns
Shared model behavior lives in `app/models/concerns/`. Examples:
- Encryptable data patterns
- Common scopes
- State machine definitions (via AASM gem)

### Testing Structure
Both RSpec (`spec/`) and Minitest (`test/`) coexist. New tests should follow the existing pattern for the model/controller being tested.

System tests use Capybara + Selenium WebDriver.

### Audit Logging
All console access is audited via Console1984. In production and staging, `bin/rails console` and `bin/rails dbconsole` wait until the person who started them signs them in at `/admin/console_access`, and the session is recorded under that person. The app's database role (`weave_app`) cannot delete or rewrite the audit tables. `dbconsole` opens an audited SQL console, not psql. Details: `docs/CONSOLE_ACCESS.md`. Reviewers read the sessions at `/admin/console` (Audits1984).

## UI
Weave is the reference implementation of the Patchwork design system. Read `docs/UI.md` before you touch a view. The guide (principles, tokens, components, icons) is in internal-docs under `design/`.

- Tokens and component classes: `app/assets/tailwind/application.css`. Use token utilities (`bg-paper`, `text-ink-soft`, `border-hairline`), never a hex, a raw Tailwind palette color or an inline `style=""`.
- Helpers: `page_header`, `badge`, `nav_link`, `empty_state`, `form_errors`, `copy_button`, `avatar`, `dl_row` (`app/helpers/ui_helper.rb`), `time_label` (`app/helpers/time_helper.rb`) and `icon(:name)` (Lucide, `app/helpers/icon_helper.rb`). No emoji in the interface.
- Every date and time goes through `time_label`. Never call `strftime`, `to_fs`, `l` or `time_ago_in_words` in a view.
- The public identifier is the "Weave ID" in every label and message. Not "PWL ID", not "P_ID".
- One `btn-primary` per rendered page: the main safe action, never a destructive or high-risk one. Danger actions confirm first. A form with `data: { turbo: false }` confirms through the `confirm-submit` controller, because Turbo ignores `data-turbo-confirm` on it.
- Every page works at 390px and in dark mode, and with the keyboard: the skip link and `id="main"` stay in every layout, focus is an outline, a drawer moves focus in and out, a wide table sits in `.table-wrap`.
- Copy: sentence case for labels and buttons, no title case. Flash notices read as plain sentences ("The group was updated.", not "Group was successfully updated."). Optional fields say "(optional)" in the label; required fields carry no marker.
- Long optional blocks (addresses, integration notes) fold into `<details class="card">` with the `.card-header` as the `<summary>`.
- Every page has `content_for :title`. Admin pages go in the sidebar (`shared/_sidebar`) and the command bar (`shared/_command_bar`).
- `spec/ui/view_conventions_spec.rb` enforces the rules a file scan can hold. Run it before you commit a view. When you add a rule to `docs/UI.md`, add a check there too.
- Before a UI pull request, look at every changed page at 1280 and 390 wide, light and dark, and tab through it once. Screenshots in the PR body.

## Deployment
Production runs as Docker containers on the `alastor` NixOS host. The image is built on Ruby Alpine (`Dockerfile`). Thruster handles HTTP acceleration inside the image.

- The infra repo (`~/dev/infra`, module `modules/weave/default.nix`) defines the containers. Deploy infra changes with `deploy .#alastor --remote-build --skip-checks`.
- Production deploys are manual: `bin/deploy-local` (primary) or `gh workflow run deploy.yml` (fallback). A push to `main` does not deploy production.
- Runtime env vars (for example `RAILS_MASTER_KEY`, `MAPBOX_ACCESS_TOKEN`) live in the agenix secrets `secrets/weave-env.age` and `secrets/weave-staging-env.age` in the infra repo, not in this repo. A container reads its env file only at start, so restart the service after a secret change.

Staging (`weave-staging.patchworklabs.org`) runs the production image with `RAILS_ENV=production` plus `WEAVE_ENV=staging` and `APP_HOST`. It deploys on every push to `main` (`.github/workflows/deploy-staging.yml`). Read the deployment and host through `Weave.staging?` / `Weave.host` / `Weave.url` (`lib/weave.rb`), never `Rails.env.staging?` or a hardcoded host. Details: `docs/STAGING.md`.

Health check endpoint: `GET /up`
