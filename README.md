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
| `SHIB_ATTRIBUTES` | No | - | Shibboleth attributes to forward as HTTP headers (comma-separated). **Your backend must read only these.** See [Shibboleth Attributes](#shibboleth-attributes). |
| `SHIB_SESSION_PROPERTIES` | No | `Shib-Identity-Provider,Shib-Authentication-Instant,Shib-AuthnContext-Class` | Session properties to forward as HTTP headers (comma-separated). **Your backend must read only these.** Set to `""` to disable. See [Session Properties](#session-properties). |
| `SHIB_RETURN_URL` | No | `/` | Return URL after authentication (e.g., `/welcome`, `/dashboard`) |
| `SHIB_SP_KEY` | No | - | Content of existing Shibboleth private key (sp-key.pem) to use instead of generating new ones. Can be plain text (starting with `-----BEGIN`) or base64 encoded. |
| `SHIB_SP_CERT` | No | - | Content of existing Shibboleth public certificate (sp-cert.pem) to use instead of generating new ones. Can be plain text (starting with `-----BEGIN`) or base64 encoded. |
| `APACHE_CUSTOM_CONFIG` | No | - | Custom Apache directives for config |

> **Warning:** your backend must read **only** the `X-Shib-*` headers derived from `SHIB_ATTRIBUTES` and `SHIB_SESSION_PROPERTIES`. Those are the only ones this image clears from incoming requests, and therefore the only ones a client cannot forge. Any other `X-Shib-*` header is client input. See [Header Trust](#header-trust).

> **Note:** Environment variables are complementary and can be used together, including with custom Apache configuration files.

> **Important:** Shibboleth and Apache configurations are generated **only on first startup**. If you modify environment variables, you will need to recreate the container.

> **Note:** `SHIB_ALLOWED_USERS` applies globally to **all** paths in `SHIB_PROTECTED_PATHS`. You cannot configure different users for different paths. If you need per-path authorization, see [Advanced Apache Configucation](#advanced-apache-configuration-optional) to define specific `<Location>` blocks and set `SHIB_PROTECTED_PATHS=""` to disable automatic protection.

### Configuration Methods

This image does **not** provide a default proxy behavior. You **must** provide your own Apache configuration.

**Two methods:**

1. **`APACHE_CUSTOM_CONFIG` environment variable** (recommended for Kubernetes)
2. **Mount configuration files to `/etc/apache2/vhost.d/`** (recommended for Docker Compose)

Both methods can be used together. See `examples/php-admin-protected/docker-compose.yml` for an example on how to use it.

#### Proxy Configuration (Required)

Your custom configuration **must** define where Apache forwards requests.

See [Custom Apache Configuration](#custom-apache-configuration) for the expected setup.

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

You can provide existing certificates via environment variables `SHIB_SP_KEY` and `SHIB_SP_CERT` or let the container auto-generate new certificates on startup. These variables accept either **plain text** or **base64-encoded** strings.

If you generate certificates on startup, **you must** persist them with a volume mount to `/var/lib/shibboleth/`.

**.env example with existing certificates (plain text):**
```bash
SHIB_SP_KEY="-----BEGIN PRIVATE KEY-----
[Your private key content here]
-----END PRIVATE KEY-----"

SHIB_SP_CERT="-----BEGIN CERTIFICATE-----
[Your certificate content here]
-----END CERTIFICATE-----"
```

**.env example with existing certificates (base64 encoded):**
```bash
SHIB_SP_KEY="LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCllvdXIgcHJpdmF0ZSBrZXk...="
SHIB_SP_CERT="LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCllvdXIgY2VydGlmaWNhdGU...="
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

Shibboleth attributes received from the Identity Provider (IdP) are forwarded to your backend as HTTP headers with the `X-Shib-` prefix. **Only the attributes you list in `SHIB_ATTRIBUTES` are forwarded, and only those may be trusted by your backend** — see [Header Trust](#header-trust).

**Header naming convention:**

The attribute name is transformed to create the HTTP header name:
- Attribute: `mail` → Header: `X-Shib-Mail`
- Attribute: `givenName` → Header: `X-Shib-GivenName`
- Attribute: `persistent-id` → Header: `X-Shib-PersistentId`

The transformation capitalizes the first letter and converts hyphens/underscores followed by lowercase letters to uppercase.

### Session Properties

Beyond the attributes released by the IdP, `mod_shib` exposes properties describing the session itself. They are configured separately, with `SHIB_SESSION_PROPERTIES`. **Only the properties you list in `SHIB_SESSION_PROPERTIES` are forwarded, and only those may be trusted by your backend** — see [Header Trust](#header-trust).

Their name already starts with `Shib-`, so the header is simply the property prefixed with `X-`:
- Property: `Shib-Identity-Provider` → Header: `X-Shib-Identity-Provider`

**Forwarded by default:**

| Property | Content |
|----------|---------|
| `Shib-Identity-Provider` | entityID of the IdP the user authenticated against |
| `Shib-Authentication-Instant` | Timestamp of the authentication |
| `Shib-AuthnContext-Class` | AuthnContextClassRef, e.g. to detect MFA |

**Also available**, if you add them to `SHIB_SESSION_PROPERTIES`: `Shib-Session-Expires`, `Shib-Session-Index` (needed for Single Logout), `Shib-Session-ID`, `Shib-Session-Inactivity`, `Shib-AuthnContext-Decl`, `Shib-Application-ID`, `Shib-Handler`. Listing one is what makes it usable: a property left out is never set, so its header stays forgeable.

```yaml
SHIB_SESSION_PROPERTIES: "Shib-Identity-Provider,Shib-Session-Index"
SHIB_SESSION_PROPERTIES: ""   # Forward none
```

### Header Trust

Your backend authenticates users by trusting these headers, so they must be impossible to forge. Three conditions:

1. **The proxy strips them.** Each forwarded attribute or session property is generated as a pair of directives:

   ```apache
   RequestHeader unset X-Shib-Mail
   RequestHeader set X-Shib-Mail %{mail}e env=mail
   ```

   The `unset` matters: `set` only overwrites the header when the attribute is present in the session, so on an unprotected path — or for an attribute the IdP did not release — a header forged by the client would otherwise reach your backend untouched.

2. **Your backend is only reachable through the proxy.** Publish no port for it (internal Docker network, or a `ClusterIP` Service in Kubernetes). Otherwise anyone can call it directly with forged headers and bypass Shibboleth entirely.

3. **Your backend reads only what is forwarded.** The image clears exactly the headers it sets — those derived from `SHIB_ATTRIBUTES` and `SHIB_SESSION_PROPERTIES`, and nothing else. There is no wildcard: an `X-Shib-*` header you did not configure is neither set nor cleared, so it arrives exactly as the client sent it.

   ```php
   $_SERVER['HTTP_X_SHIB_MAIL']      // configured in SHIB_ATTRIBUTES → trustworthy
   $_SERVER['HTTP_X_SHIB_EPPN']      // not configured → forged by anyone
   ```

   The failure is silent and reads like working code: no error, no empty value, just an attacker-chosen identity. Before trusting a header in your backend, check that the matching attribute or property is in your configuration.

#### Recommended Configuration

**Best practice:** Forward only the attributes your application actually needs. Every extra attribute is one more piece of personal data crossing to your backend, for no benefit.

```yaml
SHIB_ATTRIBUTES: "mail,givenName,surname,uniqueID"
```

There is no auto-detection: attributes are listed by hand, deliberately. The list defines both what your backend receives *and* what it is allowed to trust, so it has to be a decision, not a discovery — an attribute that appears silently because the metadata changed is an attribute nobody reviewed.

**Important:** Use the attribute names as defined in `/etc/shibboleth/attribute-map.xml` (not the FriendlyName from metadata).

**Finding the attributes available to you:**

1. After authenticating, visit `https://your-domain.ch/Shibboleth.sso/Session` - it lists the attributes actually received for the current session, under the names to use here
2. Your SP metadata declares what you may receive: `https://rr.aai.switch.ch/entity/resource/<RESOURCE_ID>/metadata.xml`
3. For the complete federation catalog, see the [SWITCH AAI Attributes Documentation](https://help.switch.ch/aai/support/documents/attributes/)

**Attribute availability:** Not all attributes are always available. Availability depends on your organization's Identity Provider configuration, on what your SP is allowed to receive, and on user consent for attribute release. An attribute that is listed but never released simply yields no header - your backend must handle it being absent.

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


## Custom Apache Configuration

What the container does is entirely up to your configuration: it is included inside the `<VirtualHost>` (see [Configuration Methods](#configuration-methods)), so any directive Apache accepts is valid there — rewrite rules, `<Location>` blocks, headers, cache control, and so on.

That said, the image is **designed to be used as a full proxy**: it terminates Shibboleth, then forwards every request to your application. Your files stay in your application image, so the same configuration works in Docker Compose and Kubernetes.

**custom.conf:**
```apache
# Proxy everything to the backend
ProxyPass / http://backend:8080/
ProxyPassReverse / http://backend:8080/
```

Your backend serves both dynamic responses and static assets.

Shibboleth attributes are forwarded as `X-Shib-*` headers, so the backend still knows who the user is.

> **Security:** your backend must be reachable **only** through this proxy (internal Docker network / `ClusterIP` Service, no published port), otherwise the `X-Shib-*` headers can be spoofed by bypassing authentication. See [Header Trust](#header-trust).

Other layouts are possible — Apache can serve files itself (see below), or proxy only some paths — but they require those files to be present in this container (you can extend this image and copy your static files into it), which the full proxy avoids.

**custom.conf (Apache serving the files itself):**
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
    SetHandler "proxy:fcgi://php-fpm:9000/"
</FilesMatch>
```

A complete `docker-compose` example is available in the [examples](examples/) folder.

## Documentation

- [Shibboleth SP Documentation](https://shibboleth.atlassian.net/wiki/spaces/SP3/overview)
- [SWITCHaai Documentation](https://www.switch.ch/aai/)
- [Apache Documentation](https://httpd.apache.org/docs/2.4/)
