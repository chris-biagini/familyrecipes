# Content Security Policy Design

GitHub issue: #87

## Problem

The CSP initializer exists but is entirely commented out. No `Content-Security-Policy` header is sent. The app has multiple `html_safe` calls in recipe rendering (processed instructions, nutrition table, Redcarpet markdown output). A CSP provides defense-in-depth: even if an escaping bug leaks a `<script>` tag, the browser blocks execution.

## Current State

The app is already CSP-friendly:

- **Zero inline scripts or styles.** All JS is in external files loaded via `javascript_include_tag`. All CSS is in external stylesheets via `stylesheet_link_tag`.
- **No external resources.** No CDN fonts, analytics, or external images. No `@import`, no `data:` URIs in CSS.
- **ActionCable** uses `ActionCable.createConsumer()` from an external JS file — only needs WebSocket allowlisted in `connect-src`.

## Design Decision: Simple Self-Only Policy

A nonce-based policy was considered and rejected. Nonces add per-request complexity for zero benefit when there are no inline scripts to allowlist. The project philosophy already mandates external JS files, so this shouldn't change.

## Policy Directives

| Directive     | Value              | Rationale                                      |
|---------------|--------------------|-------------------------------------------------|
| `default_src` | `:self`            | Fallback — only allow same-origin               |
| `script_src`  | `:self`            | All JS is external files via Propshaft           |
| `style_src`   | `:self`            | All CSS is external stylesheets via Propshaft    |
| `img_src`     | `:self`            | All images are self-hosted assets                |
| `font_src`    | `:self`            | No external fonts                                |
| `connect_src` | `:self`, `ws:`, `wss:` | Fetch/XHR to self + ActionCable WebSockets  |
| `object_src`  | `:none`            | No Flash/plugins                                 |
| `frame_src`   | `:none`            | No iframes                                       |
| `base_uri`    | `:self`            | Prevent `<base>` tag injection                   |
| `form_action` | `:self`            | Forms only submit to same origin                 |

No nonce generator. No violation reporting endpoint. Enforcing mode (not report-only).

## Implementation Scope

**One file changes:** `config/initializers/content_security_policy.rb` — replace the commented boilerplate with the policy above.

**Testing:** Integration test asserting the `Content-Security-Policy` header is present with expected directives. Manual verification that ActionCable connects on the groceries page without console errors.

**No other files change.** No views, no JS, no routes.

## Future Considerations

- If inline scripts are ever needed, upgrade to nonce-based policy via `content_security_policy_nonce_generator`.
- If a violation reporting endpoint becomes useful, add a controller at `/csp-reports` and set `report_uri`.
- If external resources are added (fonts, CDN, analytics), update the relevant directive.
