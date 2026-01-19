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
SHIB_PROTECTED_PATHS: "/aai"     # Aplication login endpoint
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
| `SHIB_RETURN_URL` | No | `/` | Return URL after authentication (e.g., `/welcome`, `/dashboard`) |
| `APACHE_CUSTOM_CONFIG` | No | - | Custom Apache directives for config |

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

### Shibboleth Certificates Persistence (Required)

Shibboleth certificates **must be persisted** to avoid regeneration on every container restart. Mount a volume to `/var/lib/shibboleth/`.

The certificates are auto-generated on first startup and used to authenticate with the SAML Identity Provider (IdP). If they change, you must re-register your certificat on AAI Resource Registry (https://rr.aai.switch.ch/) and wait for propagation.

## Shibboleth Attributes

Attributes are automatically forwarded as HTTP headers, use it in your app as needed:

- `X-Shib-Identity-Provider`: Identity provider URL
- `X-Shib-eppn`: eduPersonPrincipalName
- `X-Shib-mail`: Email
- `X-Shib-displayName`: Full name
- `X-Shib-givenName`: First name
- `X-Shib-sn`: Last name

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
