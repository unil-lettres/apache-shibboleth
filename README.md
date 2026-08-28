# Apache Shibboleth Proxy

Docker image providing **Apache as reverse proxy** with **Shibboleth SP** pre-configured for SWITCHaai.

## Shibboleth Protection

Two ways to use Shibboleth, depending on whether your application manages its own users.

### Case 1: Application with User Management

Only the **login endpoint** needs protection, the rest of the site stays public. Shibboleth authenticates there, your backend reads the `X-Shib-*` headers to create or update the user record, then runs on its own session (cookie, JWT).

```yaml
SHIB_PROTECTED_PATHS: "/aai"     # Application login endpoint
```

### Case 2: Application without User Management

Shibboleth guards the paths itself and blocks unauthenticated users. No session handling on your side.

```yaml
SHIB_PROTECTED_PATHS: "/"                 # (default) Protect all site
# or
SHIB_PROTECTED_PATHS: "/admin,/secured"   # Protect specific sections
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description                                                                                                                                                                    |
|----------|----------|---------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `SHIB_HOSTNAME` | Yes | - | Your domain name                                                                                                                                                               |
| `SHIB_CONTACT` | Yes | - | Contact email                                                                                                                                                                  |
| `SHIB_ENTITY_ID` | No | - | If entityID is not the same as the hostname (when multiple locations registered for the same entityID). You must only specify the `host` part of the ID.                       |
| `SHIB_PROTECTED_PATHS` | No | `/` | Paths to protect with Shibboleth (comma-separated). Set to empty string `""` to disable protection and configure manually.                                                     |
| `SHIB_ALLOWED_USERS` | No | - | Restrict access to specific users by uniqueID (comma-separated, e.g., `user@domain.ch,other@domain.ch`)                                                                        |
| `SHIB_ATTRIBUTES` | No | - | Shibboleth attributes to forward as HTTP headers (comma-separated). **Your backend must read only these.** See [Shibboleth Attributes](#shibboleth-attributes).                |
| `SHIB_SESSION_PROPERTIES` | No | `Shib-Identity-Provider,Shib-Authentication-Instant,Shib-AuthnContext-Class` | Session properties to forward as HTTP headers (comma-separated). **Your backend must read only these.** Set to `""` to disable. See [Session Properties](#session-properties). |
| `SHIB_RETURN_URL` | No | `/` | Return URL after authentication (e.g., `/welcome`, `/dashboard`)                                                                                                               |
| `SHIB_SP_KEY` | No | - | Content of existing Shibboleth private key (sp-key.pem) to use instead of generating new ones. Can be plain text (starting with `-----BEGIN`) or base64 encoded.               |
| `SHIB_SP_CERT` | No | - | Content of existing Shibboleth public certificate (sp-cert.pem) to use instead of generating new ones. Can be plain text (starting with `-----BEGIN`) or base64 encoded.       |
| `SECURITY_HEADERS_ENABLED` | No | `false` | Enable or disable the Apache security headers [`config/security-headers.conf`](config/security-headers.conf)                                                                                                                        |
| `APACHE_CUSTOM_CONFIG` | No | - | Custom Apache directives for config                                                                                                                                            |

> **Security concern:**
>
> Your backend must be reachable **only** through this proxy, otherwise anyone can call it directly with forged headers and bypass Shibboleth entirely.
>
> It must read **only** the headers derived from `SHIB_ATTRIBUTES` and `SHIB_SESSION_PROPERTIES`, the only ones the proxy clears from incoming requests.

> **Note:** Environment variables are complementary and can be used together, including with custom Apache configuration files.

> **Important:** Shibboleth and Apache configurations are generated **only on first startup**. Changing an environment variable requires recreating the container.

> **Note:** `SHIB_ALLOWED_USERS` applies to **all** paths in `SHIB_PROTECTED_PATHS` at once. For per-path authorization, set `SHIB_PROTECTED_PATHS=""` and define your own `<Location>` blocks — see [Advanced directives](#advanced-directives).

### Apache Configuration

This image does **not** provide a default proxy behavior: you **must** supply your own Apache configuration, and it **must** define where Apache forwards requests. It is included inside the `<VirtualHost>`, so any directive Apache accepts is valid there — rewrite rules, `<Location>` blocks, headers, cache control.

**Two ways to provide it**, usable together — see [examples/php-admin-protected/docker-compose.yml](examples/php-admin-protected/docker-compose.yml) for both:

1. **`APACHE_CUSTOM_CONFIG` environment variable** (recommended for Kubernetes)
1. **Mount configuration files to `/etc/apache2/vhost.d/`** (recommended for Docker Compose)

#### Full proxy (recommended)

The image is designed to terminate Shibboleth, then forward every request to your application. Your files stay in your application image, so the same configuration works in Docker Compose and Kubernetes.

```apache
# Proxy everything to the backend
ProxyPass / http://backend:8080/
ProxyPassReverse / http://backend:8080/
```

Attributes are forwarded as `X-Shib-*` headers, so the backend still knows who the user is.

#### Advanced directives

Any Apache directive works, for example per-path authorization:

```apache
<Location /secured>
    AuthType shibboleth
    ShibRequestSetting requireSession true
    Require shib-attr uniqueID secured@domain.ch
</Location>
```

For complex scenarios, set `SHIB_PROTECTED_PATHS=""` to disable automatic protection and manage every `<Location>` block yourself.

A complete `docker-compose` example is available in the [examples](examples/) folder.

### Shibboleth Certificates

The SP authenticates to the Identity Provider with a key pair, `sp-key.pem` and `sp-cert.pem`, stored in `/var/lib/shibboleth/`. If they change, you must re-register the certificate on [AAI Resource Registry](https://rr.aai.switch.ch/) and wait for propagation.

Either provide existing certificates through `SHIB_SP_KEY` and `SHIB_SP_CERT` — as plain text or base64-encoded — or let the container generate them on first startup, in which case **you must** persist them with a volume:

```yaml
services:
  apache-shibboleth:
    volumes:
      - shibboleth-certs:/var/lib/shibboleth

volumes:
  shibboleth-certs:
```

**.env example with existing certificates:**
```bash
SHIB_SP_KEY="-----BEGIN PRIVATE KEY-----
[Your private key content here]
-----END PRIVATE KEY-----"

SHIB_SP_CERT="-----BEGIN CERTIFICATE-----
[Your certificate content here]
-----END CERTIFICATE-----"
```

**Certificate rollover:** when renewing (e.g. for expiration), follow the [SWITCH certificate rollover guide](https://help.switch.ch/aai/guides/sp/certificate-rollover/) to avoid service interruptions: add the new certificate alongside the old one, wait for metadata propagation (≈2 hours), then switch to the new one and remove the old one.

### Ports

The Apache proxy listens on **port 8080** (HTTP). This container is designed to run behind a TLS termination proxy that handles HTTPS.

### Shibboleth Attributes

Attributes released by the Identity Provider are forwarded to your backend as `X-Shib-*` headers. **Only those listed in `SHIB_ATTRIBUTES` are forwarded, and only those may be trusted**: the list defines what your backend receives *and* what it is allowed to trust, so keep it to what the application actually needs.

```yaml
SHIB_ATTRIBUTES: "mail,givenName,surname,uniqueID"
```

**Header naming:** the first letter is capitalized, and hyphens or underscores followed by a lowercase letter become uppercase.
- `mail` → `X-Shib-Mail`
- `persistent-id` → `X-Shib-PersistentId`

**Important:** use the attribute names defined in `/etc/shibboleth/attribute-map.xml`, not the FriendlyName from metadata. To see what you actually receive, authenticate then visit `https://your-domain.ch/Shibboleth.sso/Session`: it lists the attributes of the current session, under the names to use here. The complete federation catalog is in the [SWITCH AAI Attributes Documentation](https://help.switch.ch/aai/support/documents/attributes/).


### Session Properties

Beyond the attributes released by the IdP, `mod_shib` exposes properties describing the session itself. They are configured separately, with `SHIB_SESSION_PROPERTIES`. Their name already starts with `Shib-`, so the header is simply the property prefixed with `X-`: `Shib-Identity-Provider` → `X-Shib-Identity-Provider`.

**Forwarded by default:**

| Property | Content |
|----------|---------|
| `Shib-Identity-Provider` | entityID of the IdP the user authenticated against |
| `Shib-Authentication-Instant` | Timestamp of the authentication |
| `Shib-AuthnContext-Class` | AuthnContextClassRef, e.g. to detect MFA |

```yaml
SHIB_SESSION_PROPERTIES: "Shib-Identity-Provider,Shib-Session-Index"
SHIB_SESSION_PROPERTIES: ""   # Forward none
```

## Docker images

GitHub Actions workflows generate Docker image tags based on these events:
- Push to `development`: `dev-latest`
- Push to `main`: `latest`
- Push a git tag: `vX.Y.Z` (immutable)

Weekly cron jobs:
- Create an updated production candidate: `vX.Y.Z-<sha>-<timestamp>` (immutable, from git tag)

## Documentation

- [Shibboleth SP Documentation](https://shibboleth.atlassian.net/wiki/spaces/SP3/overview)
- [SWITCHaai Documentation](https://www.switch.ch/aai/)
- [Apache Documentation](https://httpd.apache.org/docs/2.4/)
