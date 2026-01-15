# PHP Application with Protected Admin Area

This example demonstrates a PHP application with:
- Public homepage (no authentication)
- Protected `/admin` area (requires Shibboleth authentication)
- Protected `/bob` area (requires Shibboleth authentication for uniqueID bob@domain.ch)

## Structure

```
.
├── docker-compose.yml
├── custom.conf          # Apache custom configuration
└── app/
    ├── index.php        # Public page
    └── admin/
        └── index.php    # Protected page (Shibboleth required)
```

## How it works

1. **Public access**: `/` is accessible without authentication
2. **Protected access**: `/admin` requires Shibboleth authentication
2. **Protected access**: `/bob` requires Shibboleth authentication for uniqueID bob@domain.ch
3. **PHP-FPM**: Only `.php` files are processed by PHP-FPM
4. **Static files**: CSS, JS, images served directly by Apache

## Run the example

```bash
# From this directory
docker compose up --build

# Access
# http://localhost:8080/        → Public
# http://localhost:8080/admin/  → Protected (redirects to SWITCHaai)
```

## Important Notes

⚠️ **Development/Testing Limitations:**

For real Shibboleth authentication to work, you need:

1. **Valid hostname**: Replace `localhost:8080` with a real domain
2. **SP Registration**: Register your Service Provider in [SWITCHaai Resource Registry](https://rr.aai.switch.ch/)
3. **SSL Certificate**: SWITCHaai requires HTTPS (use reverse proxy with SSL in front)
