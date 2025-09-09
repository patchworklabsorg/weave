# Patchwork Labs IDP Setup Guide

A comprehensive guide to set up the Patchwork Labs Identity Provider (IDP) application locally.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Ruby**: Version 3.4.3 (specified in `.ruby-version`)
- **Node.js**: For JavaScript dependencies
- **Bun**: JavaScript runtime and package manager
- **PostgreSQL**: Version 17 (or compatible)
- **Redis**: Version 7 (or compatible)
- **Docker** (optional): For containerized setup

## Quick Start

### Option 1: Local Development Setup

1. **Clone and Navigate to Repository**
   ```bash
   cd /path/to/patchwork/idp
   ```

2. **Install Ruby Dependencies**
   ```bash
   bundle install
   ```

3. **Install JavaScript Dependencies**
   ```bash
   bun install
   ```

4. **Set Up Environment Variables**
   - Copy the example environment file:
   ```bash
   cp .env.example .env  # If .env.example exists, otherwise create .env
   ```
   - Update `.env` with your local settings:
   ```env
   RAILS_ENV=development
   DATABASE_USER=your_postgres_user
   DATABASE_PASSWORD=your_postgres_password
   RAILS_MASTER_KEY=your_rails_master_key
   ```

5. **Start Required Services**
   - Start PostgreSQL and Redis locally, or use Docker:
   ```bash
   docker run -d --name postgres -p 5432:5432 -e POSTGRES_USER=jsp -e POSTGRES_PASSWORD=jsp postgres:17
   docker run -d --name redis -p 6379:6379 redis:7-alpine
   ```

6. **Set Up Database**
   ```bash
   bin/rails db:create
   bin/rails db:migrate
   bin/rails db:seed  # If seed file exists
   ```

7. **Build Assets**
   ```bash
   bun run build
   bin/rails assets:precompile  # If needed
   ```

8. **Start Development Server**
   ```bash
   bin/dev  # Uses Procfile.dev to start all services
   # OR start individually:
   bin/rails server  # Web server
   bin/rails tailwindcss:watch  # CSS compilation
   yarn build --watch  # JavaScript bundling
   ```

9. **Access Application**
   - Open your browser to: http://localhost:3000

### Option 2: Docker Setup

1. **Build Docker Image**
   ```bash
   docker build -t patchwork-idp:local .
   ```

2. **Set Up Environment**
   - Ensure `.env` file is configured with your settings

3. **Start Services with Docker Compose**
   ```bash
   docker-compose up -d
   ```

4. **Set Up Database**
   ```bash
   docker-compose exec web bin/rails db:create db:migrate
   ```

5. **Access Application**
   - Open your browser to: http://localhost

## Configuration

### Environment Variables

Key environment variables to configure:

```env
# Rails Configuration
RAILS_ENV=development
RAILS_MASTER_KEY=your_rails_master_key

# Database Configuration
DATABASE_USER=your_postgres_user
DATABASE_PASSWORD=your_postgres_password

# Security
HASH_KEY=your_hash_key_for_encryption

# External Services (if applicable)
REDIS_URL=redis://localhost:6379
DATABASE_URL=postgres://user:password@localhost/patchwork-idp_development
```

### Database Setup

The application uses PostgreSQL with the following features:
- Full-text search (pg_search)
- Soft deletions (acts_as_paranoid)
- Change tracking (paper_trail)
- Safe migrations (strong_migrations)

### Key Features Enabled

This IDP application includes:
- **Authentication**: WebAuthn, OAuth 2.0 provider (Doorkeeper)
- **Security**: Rate limiting, CORS, encryption (Lockbox)
- **Background Jobs**: Solid Queue for job processing
- **Caching**: Redis for session storage and caching
- **Monitoring**: Health checks (okcomputer), analytics (ahoy_matey)
- **Admin Tools**: Flipper for feature flags, Blazer for BI dashboard

## Development Tools

### Available Commands

```bash
# Start all development services
bin/dev

# Run tests
bin/rails test
rspec  # If using RSpec

# Code quality checks
rubocop  # Ruby linting
brakeman  # Security analysis

# Database operations
bin/rails db:migrate
bin/rails db:rollback
bin/rails db:reset

# Asset compilation
bun run build
bin/rails tailwindcss:build
```

### Development URLs

When running locally:
- **Main Application**: http://localhost:3000
- **Letter Opener** (Email Preview): http://localhost:3000/letter_opener
- **Flipper UI** (Feature Flags): http://localhost:3000/flipper
- **Blazer** (BI Dashboard): http://localhost:3000/blazer

## Troubleshooting

### Common Issues

1. **Database Connection Issues**
   - Ensure PostgreSQL is running
   - Check DATABASE_URL in your environment
   - Verify user credentials

2. **Asset Compilation Errors**
   - Run `bun install` to ensure all JavaScript dependencies are installed
   - Check that Node.js version is compatible

3. **Bundle Install Failures**
   - Ensure Ruby version 3.4.3 is installed
   - Check for system dependencies (libpq-dev, build-essential on Ubuntu)

4. **Redis Connection Issues**
   - Ensure Redis is running on port 6379
   - Check REDIS_URL environment variable

### Getting Help

- Check application logs in `log/development.log`
- Review the Rails console: `bin/rails console`
- Use the debugging tools available in development mode

## Production Deployment

This application is configured for deployment with:
- **Kamal**: Docker container deployment
- **Thruster**: HTTP asset caching and acceleration
- **Health Checks**: Available at `/up` endpoint

For production deployment, ensure all environment variables are properly configured and secrets are secured.