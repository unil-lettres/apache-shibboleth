# PHP Application with Protected Admin Area

This example demonstrates a PHP application behind the Shibboleth proxy:
- Public homepage (no authentication)
- Protected `/admin` area (requires Shibboleth authentication)
- Protected `/bob` area (requires Shibboleth authentication for uniqueID bob@domain.ch)

## Structure

```
.
├── docker-compose.yml
├── custom.conf          # Apache custom configuration (full proxy)
└── app/
    ├── index.php        # Public page
    └── admin/
        └── index.php    # Protected page (Shibboleth required)
```

## How it works

Two containers, each with one job:

```
client → apache-shibboleth (SAML, port 8080) → app (php:8.4-apache, port 80)
```

1. **`apache-shibboleth`** authenticates and proxies **everything** to `app` - it never touches your application files
2. **`app`** serves the PHP pages and their static assets
3. **Public access**: `/` is accessible without authentication
4. **Protected access**: `/admin` requires Shibboleth authentication, `/bob` requires uniqueID `bob@domain.ch`
5. **Attributes**: forwarded to `app` as `X-Shib-*` HTTP headers

The `app` container publishes **no port**: it must only be reachable through the proxy, otherwise anyone could call it directly with forged `X-Shib-*` headers and bypass authentication entirely.

## Run the example

```bash
# From this directory
docker compose up --build

# Access
# http://localhost:8080/        → Public
# http://localhost:8080/admin/  → Protected (redirects to SWITCHaai)
```

## Moving to production

The only development-specific part is the `./app` bind mount on the `app` service. Replace it with your own image containing the code:

```yaml
  app:
    image: myapp:1.4.2   # or: build: .
```

## Important Notes

⚠️ **Development/Testing Limitations:**

For real Shibboleth authentication to work, you need:

1. **Valid hostname**: Replace `localhost:8080` with a real domain
2. **SP Registration**: Register your Service Provider in [SWITCHaai Resource Registry](https://rr.aai.switch.ch/)
3. **SSL Certificate**: SWITCHaai requires HTTPS (use reverse proxy with SSL in front)
