# Patchwork Labs Identity Provider (IDP)

A comprehensive Identity Provider built with Ruby on Rails, featuring OAuth 2.0 authorization server capabilities, user authentication, and identity management.

## Features

### Authentication & Authorization
- **OAuth 2.0 Provider** - Full-featured OAuth 2.0 authorization server using [Doorkeeper](https://github.com/doorkeeper-gem/doorkeeper)
- **Multiple Authentication Methods** - Email/password, magic links, and WebAuthn support
- **Scope-based Access Control** - Fine-grained permissions (profile, email, admin)
- **PKCE Support** - Enhanced security for public OAuth clients
- **OAuth Discovery** - Standard RFC 8414 discovery endpoints

### Security
- **Rate Limiting** - Rack::Attack for request throttling
- **CORS Support** - Configurable cross-origin resource sharing
- **Encryption** - Lockbox for sensitive data encryption
- **Audit Logging** - Audits1984 for console access tracking
- **Security Analysis** - Brakeman for continuous security scanning

### User Management
- **Email Verification** - Confirmation workflow for new users
- **Profile Management** - User profiles with avatars and custom fields
- **Session Management** - Track and manage user sessions
- **Soft Deletions** - Acts as paranoid for data retention

### Background Processing
- **Solid Queue** - Database-backed Active Job adapter
- **Mission Control** - Job monitoring and management
- **Email Analytics** - Ahoy Email for tracking

### Developer Experience
- **API Documentation** - Swagger/OpenAPI via rswag
- **Feature Flags** - Flipper for gradual rollouts
- **BI Dashboard** - Blazer for business intelligence
- **Health Checks** - Comprehensive health check endpoints

## Quick Start

See [SETUP.md](SETUP.md) for detailed installation instructions.

```bash
# Install dependencies
bundle install
bun install

# Setup database
bin/rails db:create db:migrate

# Start development server
bin/dev
```

## OAuth 2.0 Provider

This IDP includes a complete OAuth 2.0 authorization server. See [docs/OAUTH.md](docs/OAUTH.md) for detailed OAuth documentation.

### Key OAuth Endpoints

- **Authorization**: `GET /oauth/authorize`
- **Token**: `POST /oauth/token`
- **UserInfo**: `GET /oauth/userinfo`
- **Revocation**: `POST /oauth/revoke`
- **Discovery**: `GET /.well-known/oauth-authorization-server`

### Supported Grant Types

- Authorization Code Grant (with PKCE)
- Client Credentials Grant
- Refresh Token Grant

## Documentation

- [Setup Guide](SETUP.md) - Detailed installation and configuration
- [OAuth Provider](docs/OAUTH.md) - OAuth 2.0 integration guide

## Technology Stack

- **Framework**: Ruby on Rails 8.0
- **Database**: PostgreSQL 17
- **Cache/Queue**: Redis 7
- **Frontend**: Turbo, Stimulus, Tailwind CSS
- **Authentication**: Doorkeeper (OAuth 2.0), WebAuthn
- **Background Jobs**: Solid Queue

## Color Palette

1. Deep Purple - #4B006E - Rich, saturated purple for bold accents
2. Lavender Purple - #C7B7E2 - Soft, light purple for gentle highlights
3. Clean White - #FFFFFF - Crisp white for contrast and clarity
4. Dark Grayish-Blue - #2C3440 - Muted, cool blue-gray for depth
5. Near-Black - #18181A - Very dark, almost black for grounding elements

## License

Copyright © 2025 Patchwork Labs
