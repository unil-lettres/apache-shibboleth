# Apache Shibboleth Proxy

Docker image providing **Apache as reverse proxy** with **Shibboleth SP** pre-configured for SWITCHaai.

## Shibboleth Protection

Two main use cases for Shibboleth authentication:

### Case 1: Application with User Management

**When your application manages its own users and sessions:**

Only the **login endpoint** needs Shibboleth protection. The rest of your site remains public.

**Flow:**
1. User visits public pages → no authentication required
2. User clicks "Login" → app redirects to Shibboleth-protected endpoint (e.g., `/aai`, `/login`)
3. Shibboleth authenticates → redirects back with user attributes in `X-Shib-*` headers
4. **Backend reads headers** to create/update user record and establish session
5. User navigates → **backend uses its own session** (cookies, JWT, etc.)

**Configuration:**
```yaml
SHIB_PROTECTED_PATHS: "/aai"     # Application login endpoint
```

### Case 2: Application without User Management

**When you don't need user accounts or sessions:**

Protect **all paths** (or specific sections). Shibboleth blocks access to unauthenticated users.

**Flow:**
1. User visits any protected page → **Shibboleth redirects to IdP** if not authenticated
1. User authenticates with institutional credentials
1. **No session management needed** → Shibboleth handles authentication
1. User can now access protected pages

**Configuration:**
```yaml
SHIB_PROTECTED_PATHS: "/"                 # (default) Protect all site
# or
SHIB_PROTECTED_PATHS: "/admin,/secured"   # Protect specific sections
```


## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SHIB_HOSTNAME` | Yes | - | Your domain name |
| `SHIB_CONTACT` | Yes | - | Contact email |
| `SHIB_ENTITY_ID` | No | - | If entityID is not the same as the hostname (when multiple locations registererd for the same entityID). You must only specify the `host` part of the ID. |
| `SHIB_PROTECTED_PATHS` | No | `/` | Paths to protect with Shibboleth (comma-separated). Set to empty string `""` to disable protection and configure manually. |
| `SHIB_ALLOWED_USERS` | No | - | Restrict access to specific users by uniqueID (comma-separated, e.g., `user@domain.ch,other@domain.ch`) |
| `SHIB_RESOURCE_ID` | No | - | AAI Resource Registry ID for automatic attribute detection from metadata (e.g., `12731`). See [Shibboleth Attributes](#shibboleth-attributes). |
| `SHIB_ATTRIBUTES` | No | - | Shibboleth attributes to forward as HTTP headers (comma-separated). Overrides auto-detection. Set to `""` to disable. See [Shibboleth Attributes](#shibboleth-attributes). |
| `SHIB_RETURN_URL` | No | `/` | Return URL after authentication (e.g., `/welcome`, `/dashboard`) |
| `SHIB_SP_KEY` | No | - | Content of existing Shibboleth private key (sp-key.pem) to use instead of generating new ones |
| `SHIB_SP_CERT` | No | - | Content of existing Shibboleth public certificate (sp-cert.pem) to use instead of generating new ones |
| `APACHE_CUSTOM_CONFIG` | No | - | Custom Apache directives for config |

> **Note:** Environment variables are complementary and can be used together, including with custom Apache configuration files.

> **Important:** Shibboleth and Apache configurations are generated **only on first startup**. If you modify environment variables, you will need to recreate the container.

> **Note:** `SHIB_ALLOWED_USERS` applies globally to **all** paths in `SHIB_PROTECTED_PATHS`. You cannot configure different users for different paths. If you need per-path authorization, see [Advanced Apache Configucation](#advanced-apache-configuration-optional) to define specific `<Location>` blocks and set `SHIB_PROTECTED_PATHS=""` to disable automatic protection.

### Custom Apache Configuration

This image does **not** provide a default proxy behavior. You **must** provide your own Apache configuration.

**Two methods:**

1. **`APACHE_CUSTOM_CONFIG` environment variable** (recommended for Kubernetes)
2. **Mount configuration files to `/etc/apache2/vhost.d/`** (recommended for Docker Compose)

Both methods can be used together.

#### Proxy Configuration (Required)

Your custom configuration **must** define how Apache handles requests: full proxy, partial proxy, static files, FilesMatch, etc.

See [Custom Configuration Examples](#custom-apache-configuration-examples) for specific configurations.

#### Advanced Apache Configuration (Optional)

You can add any Apache directives for advanced configurations.

**Example - Custom Location with different authentication:**
```apache
<Location /secured>
    # Shibboleth with specific user restriction
    AuthType shibboleth
    ShibRequestSetting requireSession true
    Require shib-attr uniqueID secured@domain.ch
</Location>

<Location /admin>
    # Shibboleth with specific user restriction
    AuthType shibboleth
    ShibRequestSetting requireSession true
    Require shib-attr uniqueID admin@domain.ch
</Location>
```

**Note:** For complex authentication scenarios, set `SHIB_PROTECTED_PATHS=""` to disable protection and manage all `<Location>` blocks manually in your custom configuration.

### Shibboleth Certificates

Certificates are used to authenticate with the SAML Identity Provider (IdP). If they change, you must re-register your certificate on [AAI Resource Registry](https://rr.aai.switch.ch/) and wait for propagation.

**Certificate files:**
- `sp-key.pem` - Private key
- `sp-cert.pem` - Public certificate

**Certificate management:**

You can provide existing certificates via environment variables `SHIB_SP_KEY` and `SHIB_SP_CERT` or let the container auto-generate new certificates on startup.

If you generate certificates on startup, **you must** persist them with a volume mount to `/var/lib/shibboleth/`.

**.env example with existing certificates:**
```bash
SHIB_SP_KEY="-----BEGIN PRIVATE KEY-----
[Your private key content here]
-----END PRIVATE KEY-----"

SHIB_SP_CERT="-----BEGIN CERTIFICATE-----
[Your certificate content here]
-----END CERTIFICATE-----"
```

**docker-compose.yml example with volume persistence:**
```yaml
services:
  apache-shibboleth:
    volumes:
      - shibboleth-certs:/var/lib/shibboleth

volumes:
  shibboleth-certs:
```

**Certificate rollover:**

When updating certificates (e.g., for expiration), follow the [SWITCH certificate rollover guide](https://help.switch.ch/aai/guides/sp/certificate-rollover/) to avoid service interruptions. The process involves adding the new certificate alongside the old one, waiting for metadata propagation (≈2 hours), then switching to the new certificate and removing the old one.

### Ports

The Apache proxy listens on **port 8080** (HTTP). This container runs is designed to run behind a TLS termination proxy that handles HTTPS.

### Shibboleth Attributes

Shibboleth attributes received from the Identity Provider (IdP) are automatically forwarded to your backend as HTTP headers with the `X-Shib-` prefix.

**Header naming convention:**

The attribute name is transformed to create the HTTP header name:
- Attribute: `mail` → Header: `X-Shib-Mail`
- Attribute: `givenName` → Header: `X-Shib-Givenname`
- Attribute: `persistent-id` → Header: `X-Shib-PersistentId`

The transformation capitalizes the first letter and converts hyphens/underscores followed by lowercase letters to uppercase.

#### Recommended Configuration

**Best practice:** Only forward the attributes your application actually needs. This minimizes header overhead and improves security by limiting data exposure.

A good starting point for most applications:

```yaml
SHIB_ATTRIBUTES: "mail,givenName,surname"
```

**Tip:** If unsure which attributes are available, temporarily use `SHIB_RESOURCE_ID` with your Resource Registry ID to see all available attributes in the startup logs, then switch to `SHIB_ATTRIBUTES` with only the ones you need.

#### Automatic Attribute Detection

Set `SHIB_RESOURCE_ID` to your AAI Resource Registry ID to enable automatic attribute detection from your metadata.

```yaml
SHIB_RESOURCE_ID: "12731"  # Your resource ID from rr.aai.switch.ch
```

The container will attempt to fetch and analyze your metadata at startup. Detected attributes are displayed in the startup logs. All detected attributes will be forwarded. If an attribute is not found in the map file, it will be ignored. If detection fails, no attributes will be forwarded.

**Finding your Resource ID:**
1. Log in to [AAI Resource Registry](https://rr.aai.switch.ch/)
2. Navigate to your Service Provider resource
3. The resource ID is in the URL (e.g., `12731`)

#### Manual Configuration

You can explicitly specify which attributes to forward:

```yaml
SHIB_ATTRIBUTES: "mail,givenName,surname,uniqueID"
```

**Important:** Use the attribute names as defined in `/etc/shibboleth/attribute-map.xml` (not the FriendlyName from metadata).

**Tip:** To see which attributes are configured in your metadata, temporarily set `SHIB_RESOURCE_ID` instead of `SHIB_ATTRIBUTES`. The startup logs will display all available attributes, helping you choose which ones to configure manually.

**Attribute availability:** Not all attributes are always available. Availability depends on:
- Your organization's Identity Provider configuration
- The attributes your SP is allowed to receive (configured in AAI Resource Registry metadata: `https://rr.aai.switch.ch/entity/resource/<RESOURCE_ID>/metadata.xml`)
- User consent for attribute release

To verify which attributes are actually available, visit `https://your-domain.ch/Shibboleth.sso/Session` after authenticating.

For a complete list of SWITCH AAI attributes, see the [SWITCH AAI Attributes Documentation](https://help.switch.ch/aai/support/documents/attributes/).

**Note:** `SHIB_ATTRIBUTES` takes precedence over auto-detection. Use it when you need specific attributes different from what's in the metadata.

#### Disable Attribute Forwarding

```yaml
SHIB_ATTRIBUTES: ""  # Empty string = no attributes forwarded
```

## Docker images

GitHub Actions workflows generate Docker image tags based on these events:
- Push to `development`: `dev-latest`
- Push to `main`: `latest`
- Push a git tag: `vX.Y.Z` (immutable)

Weekly cron jobs:
- Create an updated production candidate: `vX.Y.Z-<sha>-<timestamp>` (immutable, from git tag)


## Custom Apache Configuration Examples

You can find complete examples for `docker-compose` and `Kubernetes` in examples folder.

### Example 1: PHP-FPM (only .php files proxied)

Use with PHP-FPM backend. Static files served directly, only `.php` files go to PHP-FPM.

**custom.conf:**
```apache
# Serve static files from DocumentRoot
DocumentRoot /var/www/html

<Directory /var/www/html>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

# Only .php files go to PHP-FPM
<FilesMatch \.php$>
    SetHandler "proxy:fcgi://php-fpm:9000/var/www/html"
</FilesMatch>
```


### Example 2: Partial Proxy (Ruby, Python, Node API + static frontend)

Use when you have an API backend and static frontend files.

**custom.conf:**
```apache
# Serve static files from DocumentRoot
DocumentRoot /var/www/html

<Directory /var/www/html>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

# Only /api goes to backend
ProxyPass /api http://ruby-api:3000/api
ProxyPassReverse /api http://ruby-api:3000/api
```

### Example 3: Full Proxy

Use when everything should be proxied to the backend.

**custom.conf:**
```apache
# Proxy everything to backend
ProxyPass / http://backend:8080/
ProxyPassReverse / http://backend:8080/
```

## Documentation

- [Shibboleth SP Documentation](https://shibboleth.atlassian.net/wiki/spaces/SP3/overview)
- [SWITCHaai Documentation](https://www.switch.ch/aai/)
- [Apache Documentation](https://httpd.apache.org/docs/2.4/)
