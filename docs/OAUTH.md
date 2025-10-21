# OAuth 2.0 Provider Documentation

This Identity Provider (IDP) application uses [Doorkeeper](https://github.com/doorkeeper-gem/doorkeeper) to provide OAuth 2.0 authorization server functionality.

## Features

- **OAuth 2.0 Compliance**: Full RFC 6749 compliant authorization server
- **Multiple Grant Types**: Support for Authorization Code, Client Credentials, and Refresh Token flows
- **Scope-based Access Control**: Fine-grained permissions with scopes (profile, email, admin)
- **Token Management**: Access token generation, refresh, and revocation
- **Discovery Endpoints**: Standard OAuth 2.0 and OpenID Connect discovery support
- **PKCE Support**: Enhanced security for public clients

## OAuth 2.0 Endpoints

### Discovery Endpoints

- **OAuth 2.0 Server Metadata**: `GET /.well-known/oauth-authorization-server`
  - RFC 8414 compliant discovery endpoint
  - Returns server capabilities and endpoint URLs

- **OpenID Connect Discovery**: `GET /.well-known/openid-configuration`
  - OpenID Connect discovery endpoint
  - Returns OIDC-specific metadata

### Authorization Endpoints

- **Authorization Endpoint**: `GET /oauth/authorize`
  - Used to obtain authorization from the resource owner
  - Supports authorization code and implicit grant types

- **Token Endpoint**: `POST /oauth/token`
  - Used to exchange authorization codes for access tokens
  - Used to refresh access tokens
  - Used for client credentials grant

### Token Management

- **Revocation Endpoint**: `POST /oauth/revoke`
  - Revoke access or refresh tokens

- **Introspection Endpoint**: `POST /oauth/introspect`
  - Inspect token metadata and validity

- **Token Info**: `GET /oauth/token/info`
  - Get information about the current access token

### Resource Endpoints

- **UserInfo Endpoint**: `GET /oauth/userinfo`
  - Returns user information based on the access token
  - Respects granted scopes

## Supported Grant Types

1. **Authorization Code Grant** (Recommended for web applications)
   - Most secure OAuth 2.0 flow
   - Supports PKCE for additional security

2. **Client Credentials Grant** (For service-to-service communication)
   - Machine-to-machine authentication
   - No user interaction required

3. **Refresh Token Grant**
   - Obtain new access tokens without user interaction
   - Enabled by default

## Scopes

The OAuth provider supports the following scopes:

- `profile` (default): Access to basic profile information (name, username)
- `email`: Access to email address and verification status
- `admin`: Administrative privileges (restricted)

## Using the OAuth Provider

### 1. Register an OAuth Application

Administrators can register OAuth applications through the admin interface:

1. Navigate to `/admin/oauth_applications`
2. Click "New OAuth Application"
3. Fill in the application details:
   - **Name**: Application name
   - **Redirect URI**: Callback URL(s) for your application
   - **Scopes**: Requested scopes (space-separated)
   - **Confidential**: Whether the client can keep secrets secure

### 2. Authorization Code Flow Example

```
# Step 1: Redirect user to authorization endpoint
GET /oauth/authorize?
  client_id=YOUR_CLIENT_ID&
  redirect_uri=YOUR_REDIRECT_URI&
  response_type=code&
  scope=profile+email&
  state=RANDOM_STATE

# Step 2: User authorizes the application

# Step 3: Exchange authorization code for access token
POST /oauth/token
  grant_type=authorization_code&
  code=AUTHORIZATION_CODE&
  redirect_uri=YOUR_REDIRECT_URI&
  client_id=YOUR_CLIENT_ID&
  client_secret=YOUR_CLIENT_SECRET

# Response
{
  "access_token": "...",
  "token_type": "Bearer",
  "expires_in": 7200,
  "refresh_token": "...",
  "scope": "profile email"
}

# Step 4: Use access token to access resources
GET /oauth/userinfo
Authorization: Bearer ACCESS_TOKEN
```

### 3. Client Credentials Flow Example

```
POST /oauth/token
  grant_type=client_credentials&
  client_id=YOUR_CLIENT_ID&
  client_secret=YOUR_CLIENT_SECRET&
  scope=profile

# Response
{
  "access_token": "...",
  "token_type": "Bearer",
  "expires_in": 7200,
  "scope": "profile"
}
```

### 4. Using PKCE (Proof Key for Code Exchange)

For enhanced security, especially in public clients:

```
# Generate code verifier and challenge
code_verifier = BASE64URL(RANDOM(32))
code_challenge = BASE64URL(SHA256(code_verifier))

# Step 1: Authorization request with PKCE
GET /oauth/authorize?
  client_id=YOUR_CLIENT_ID&
  redirect_uri=YOUR_REDIRECT_URI&
  response_type=code&
  code_challenge=CODE_CHALLENGE&
  code_challenge_method=S256&
  scope=profile

# Step 2: Token request with code verifier
POST /oauth/token
  grant_type=authorization_code&
  code=AUTHORIZATION_CODE&
  redirect_uri=YOUR_REDIRECT_URI&
  client_id=YOUR_CLIENT_ID&
  code_verifier=CODE_VERIFIER
```

## Token Expiration

- **Access Tokens**: Expire after 2 hours
- **Refresh Tokens**: Can be used to obtain new access tokens without re-authorization

## Security Considerations

1. **HTTPS Required**: OAuth endpoints enforce HTTPS in production
2. **State Parameter**: Always use the state parameter to prevent CSRF attacks
3. **PKCE**: Recommended for all public clients
4. **Confidential Clients**: Store client secrets securely
5. **Token Storage**: Store tokens securely on the client side
6. **Scope Limitation**: Request only necessary scopes

## Admin Management

OAuth applications can be managed through the admin interface at `/admin/oauth_applications`:

- View all registered applications
- Create new applications
- Edit application details
- Regenerate client secrets
- Delete applications
- View application access tokens

## API Integration

For programmatic access, use the API endpoints with service key authentication or OAuth tokens:

```
# Using OAuth token
GET /api/v1/users/me
Authorization: Bearer YOUR_ACCESS_TOKEN

# Using service key (for service-to-service)
POST /api/v1/auth/authenticate
X-Service-Key: YOUR_SERVICE_KEY
```

## Troubleshooting

### Common Issues

1. **Invalid redirect_uri**: Ensure the redirect URI matches exactly what was registered
2. **Invalid client credentials**: Check client_id and client_secret
3. **Token expired**: Use refresh token to obtain a new access token
4. **Insufficient scope**: Request appropriate scopes during authorization

### Testing

You can test the OAuth flow using tools like:
- [OAuth 2.0 Playground](https://www.oauth.com/playground/)
- Postman
- cURL

Example cURL request:
```bash
curl -X POST https://your-idp-domain.com/oauth/token \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "scope=profile"
```

## Further Reading

- [OAuth 2.0 RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749)
- [OAuth 2.0 Server Metadata RFC 8414](https://datatracker.ietf.org/doc/html/rfc8414)
- [PKCE RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)
- [Doorkeeper Documentation](https://doorkeeper.gitbook.io/guides/)
