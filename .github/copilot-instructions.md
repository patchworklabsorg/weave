# Copilot Instructions for Patchwork Labs IDP

## Repository Overview

This is the Patchwork Labs Identity Provider (IDP), a comprehensive OAuth 2.0 authorization server and identity management system built with Ruby on Rails. The application provides user authentication, authorization, and profile management with enterprise-grade security features.

## Technology Stack

### Backend
- **Framework**: Ruby on Rails 8.0.2
- **Ruby Version**: 4.0.1 (see `.ruby-version`)
- **Database**: PostgreSQL 17
- **Cache/Queue**: Redis 7
- **Background Jobs**: Solid Queue (database-backed Active Job)

### Frontend
- **JavaScript**: Stimulus 3.2, Turbo Rails 8.0
- **CSS**: Tailwind CSS 4.2
- **Bundler**: Rollup (via bun)
- **Asset Pipeline**: Propshaft

### Key Gems & Libraries
- **Authentication**: Doorkeeper (OAuth 2.0), WebAuthn
- **Security**: Rack::Attack (rate limiting), Rack::CORS, Lockbox (encryption), Brakeman (security scanning)
- **Monitoring**: OkComputer (health checks), Ahoy (analytics), Audits1984 (audit logging)
- **Admin Tools**: Flipper (feature flags), Blazer (BI dashboard), Mission Control (job monitoring)
- **Data**: PaperTrail (versioning), ActsAsParanoid (soft deletes), PgSearch (full-text search)

## Coding Standards & Conventions

### Ruby Style
- Follow RuboCop rules defined in `.rubocop.yml`
- Run `bin/rubocop` before committing
- Use frozen string literals: `# frozen_string_literal: true`
- Prefer Ruby 3+ features and syntax

### Rails Conventions
- Follow Rails 8 best practices
- Use strong_migrations for safe database migrations
- Annotate models with schema information using annotaterb
- Check Zeitwerk loading: `bin/rails zeitwerk:check`

### Code Organization
- Controllers should be thin; business logic belongs in models or service objects
- Use concerns for shared behavior
- Prefer composition over inheritance
- Keep methods short and focused (single responsibility)

### Naming Conventions
- Use snake_case for files, methods, and variables
- Use CamelCase for classes and modules
- RESTful routes for resources
- Descriptive variable and method names

## Testing Guidelines

### Test Framework
- **Unit/Integration**: Both RSpec (spec/) and Minitest (test/) are available
- **System Tests**: Available in test/system/
- Run tests with: `bin/rails test` or `rspec`

### Test Coverage
- Write tests for new features and bug fixes
- Test happy paths and edge cases
- Mock external services appropriately
- Test security-critical code thoroughly

### Test Organization
- Follow existing test structure in spec/ and test/ directories
- Use fixtures for test data
- Keep tests readable and maintainable

## Security Best Practices

### Critical Security Requirements
- **Never** commit secrets, API keys, or credentials
- Use Rails encrypted credentials for sensitive data
- Validate and sanitize all user inputs
- Use strong parameters in controllers
- Implement proper authorization checks
- Follow OWASP security guidelines

### OAuth 2.0 Specific
- Properly validate redirect URIs
- Implement PKCE for public clients
- Use appropriate token expiration times
- Validate scopes and permissions
- Secure token storage and transmission

### Data Protection
- Use Lockbox for encrypting sensitive data
- Implement proper access controls
- Follow GDPR/privacy requirements
- Use soft deletes (ActsAsParanoid) for data retention

## Build & Development

### Setup Commands
```bash
bundle install          # Install Ruby dependencies
bun install            # Install JavaScript dependencies
bin/rails db:create    # Create database
bin/rails db:migrate   # Run migrations
bin/dev                # Start development server
```

### Asset Compilation
```bash
bun run build                    # Build JavaScript
bin/rails tailwindcss:build      # Build CSS
bin/rails assets:precompile      # Precompile assets (production)
```

### Quality Checks
```bash
bin/rubocop                      # Lint Ruby code
bin/brakeman --no-pager         # Security scan
bin/rails zeitwerk:check        # Check autoloading
bundle exec annotaterb models   # Update model annotations
```

### Running the Application
- Development: `bin/dev` (starts all services via Procfile.dev)
- Access at: http://localhost:3000
- Admin tools:
  - Flipper: http://localhost:3000/flipper
  - Blazer: http://localhost:3000/blazer
  - Letter Opener: http://localhost:3000/letter_opener

## Deployment

- **Platform**: Docker with Kamal
- **Asset Acceleration**: Thruster for HTTP caching and compression
- **Health Check**: Available at `/up` endpoint
- **Configuration**: See `.kamal/` directory

## OAuth 2.0 Provider

This application is an OAuth 2.0 authorization server. Key endpoints:

- **Authorization**: `GET /oauth/authorize`
- **Token**: `POST /oauth/token`
- **UserInfo**: `GET /oauth/userinfo`
- **Revocation**: `POST /oauth/revoke`
- **Discovery**: `GET /.well-known/oauth-authorization-server`

Supported grant types:
- Authorization Code (with PKCE)
- Client Credentials
- Refresh Token

See `docs/OAUTH.md` for detailed OAuth documentation.

## Common Patterns

### Creating New Features
1. Create feature flag in Flipper if needed
2. Write tests first (TDD approach)
3. Implement minimum viable code
4. Run linters and security scans
5. Update documentation if needed

### Database Changes
1. Generate migration: `bin/rails generate migration`
2. Review migration for safety (strong_migrations)
3. Run migration: `bin/rails db:migrate`
4. Update model annotations: `bundle exec annotaterb models`

### Background Jobs
- Use Solid Queue for async processing
- Keep jobs idempotent
- Handle failures gracefully
- Monitor via Mission Control

## Helpful Tips

- Check `README.md` for feature overview
- Check `SETUP.md` for detailed setup instructions
- Check `docs/OAUTH.md` for OAuth integration details
- Use `bin/rails console` for debugging
- Check `log/development.log` for application logs

## Color Palette

When working with UI components, use the defined color palette:
1. **Deep Purple**: #4B006E - Primary brand color, bold accents
2. **Lavender Purple**: #C7B7E2 - Soft highlights, secondary elements
3. **Clean White**: #FFFFFF - Backgrounds, contrast
4. **Dark Grayish-Blue**: #2C3440 - Text, subtle elements
5. **Near-Black**: #18181A - Primary text, grounding elements

## Questions?

- Review existing code for patterns and conventions
- Check documentation in `docs/` directory
- Follow Rails and Ruby community best practices
