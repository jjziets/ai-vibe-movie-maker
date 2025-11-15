# WordPress Embed Plan

## Endpoint
- Plugin route: `https://www.cryptolabs.co.za/wp-json/cryptolabs/v1/framepack/auth`.
- Returns trusted headers consumed by nginx → wrapper:
  - `X-Webui-Email`
  - `X-Webui-Name`
  - `X-User-Api-Key`
  - `X-User-Litellm-Url` (optional for parity with LiteLLM stack)

## Nginx
1. Create `framepack.ai.cryptolabs.co.za.conf` mirroring `webui.ai` config.
2. `auth_request` points to `/wp-json/cryptolabs/v1/framepack/auth`.
3. Forward sanitized headers to the container plus iframe-friendly CSP.

## WordPress Page
```php
[clai_framepack_iframe width="100%" height="1200"]
```
Shortcode renders an iframe pointing to `https://framepack.ai.cryptolabs.co.za?workflow=storyboard`.

## Wrapper Expectations
- Receives forwarded headers and ensures every `/session` call maps to a specific user directory.
- Provides `/healthz` so WordPress admin can show GPU status.
- SSE/WebSocket endpoints are proxied via nginx `/ws` path similar to Open WebUI.

## SSO Notes
- Cookies never leave `cryptolabs.co.za`; iframe relies on headers only.
- `SameSite=None` must already be enabled (matches existing Open WebUI setup).
- Logging out of WordPress invalidates the iframe session automatically because `auth_request` fails and nginx returns 401.

