# Docker Deployment Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Fix two bugs from first Docker deployment: trusted-header auth not reading Authelia headers (#104), and container UID mismatch causing bind-mount permission failures (#105).

**Architecture:** Both are targeted fixes — one in the controller + tests, one in the Dockerfile + docs. No new dependencies, no structural changes.

**Tech Stack:** Rails 8, Minitest, Docker

---

### Task 1: Fix trusted-header auth to use Rack env keys

**Files:**
- Modify: `app/controllers/application_controller.rb:49-63`

**Step 1: Edit `authenticate_from_headers`**

Replace `request.headers[]` with `request.env[]` using the `HTTP_` prefix. `Remote-User` is a CGI variable name — Rails' `request.headers['Remote-User']` resolves to `REMOTE_USER` instead of `HTTP_REMOTE_USER` where Rack stores actual HTTP headers.

```ruby
def authenticate_from_headers
  return if authenticated?

  remote_user = request.env['HTTP_REMOTE_USER']
  return unless remote_user.present?

  email = request.env['HTTP_REMOTE_EMAIL'].presence || "#{remote_user}@header.local"
  name = request.env['HTTP_REMOTE_NAME'].presence || remote_user

  user = User.find_or_create_by!(email: email) do |u|
    u.name = name
  end

  start_new_session_for(user)
end
```

Note: add `.present?` / `.presence` checks because `request.env` returns `nil` for missing keys (not empty string), and proxies may forward empty header values.

**Step 2: Run tests to confirm they break**

Run: `ruby -Itest test/controllers/header_auth_test.rb`
Expected: Multiple failures — the tests currently pass headers via `'Remote-User'` which the test framework routes through the CGI variable path. After the controller fix, the controller reads `HTTP_REMOTE_USER` but the tests only set `REMOTE_USER`.

---

### Task 2: Update header auth tests to match real proxy behavior

**Files:**
- Modify: `test/controllers/header_auth_test.rb`

**Step 1: Replace all header keys with Rack env format**

Every `headers:` hash in the test file must change from `'Remote-User'` to `'HTTP_REMOTE_USER'` (and likewise for `Remote-Name` → `HTTP_REMOTE_NAME`, `Remote-Email` → `HTTP_REMOTE_EMAIL`). This matches what Rack actually stores when a real HTTP header arrives from Caddy/Authelia.

The full set of replacements:
- `'Remote-User'` → `'HTTP_REMOTE_USER'`
- `'Remote-Name'` → `'HTTP_REMOTE_NAME'`
- `'Remote-Email'` → `'HTTP_REMOTE_EMAIL'`

Every test that passes these headers needs updating (7 tests, ~13 header hashes).

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/header_auth_test.rb`
Expected: All 8 tests pass.

**Step 3: Run full test suite**

Run: `rake test`
Expected: All tests pass. No other code references `request.headers['Remote-']`.

**Step 4: Run lint**

Run: `rake lint`
Expected: Clean.

**Step 5: Commit**

```bash
git add app/controllers/application_controller.rb test/controllers/header_auth_test.rb
git commit -m "fix: read trusted headers via request.env to avoid CGI variable collision

Closes #104"
```

---

### Task 3: Fix container UID to 1000

**Files:**
- Modify: `Dockerfile:24-28`

**Step 1: Replace system user with UID 1000**

Change the user creation from `--system` (which gets a low UID like 999) to explicit UID 1000:GID 1000, matching the Rails 8 convention and the most common Linux user UID:

```dockerfile
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libsqlite3-0 libyaml-0-2 && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --gid 1000 rails && \
    useradd --uid 1000 --gid 1000 --create-home rails
```

**Step 2: Verify Docker build**

Run: `docker build -t familyrecipes:test .`
Expected: Builds successfully with the new UID.

---

### Task 4: Add bind-mount note to README

**Files:**
- Modify: `README.md` (Backups section, after the volume description)

**Step 1: Add a note about bind mounts**

After the existing sentence about the Docker volume, add a brief note explaining the bind-mount trade-off. Insert after line 91 (`Both SQLite databases...`):

```markdown
> **Bind mounts:** The container runs as UID 1000 (the default user on most Linux systems). If you use a bind mount instead of a named volume (e.g., `./storage:/app/storage`), ensure the host directory is writable by UID 1000: `chown -R 1000:1000 ./storage`. Named volumes (the default in `docker-compose.example.yml`) handle permissions automatically.
```

**Step 2: Commit**

```bash
git add Dockerfile README.md
git commit -m "fix: use UID 1000 for container user to fix bind-mount permissions

Closes #105"
```

---

### Task 5: Update CLAUDE.md and run final verification

**Files:**
- Modify: `CLAUDE.md:325` (Trusted-header authentication section)

**Step 1: Update CLAUDE.md auth description**

Update the trusted-header auth paragraph to note the `request.env` pattern:

> In production behind Authelia/Caddy, `Remote-User`/`Remote-Email`/`Remote-Name` HTTP headers identify users. `ApplicationController#authenticate_from_headers` reads these via `request.env['HTTP_REMOTE_USER']` (not `request.headers` — `Remote-User` collides with the CGI `REMOTE_USER` variable). Subsequent requests authenticate via the session cookie — headers are only read when establishing a new session. In dev/test (no headers), `DevSessionsController` provides direct login at `/dev/login/:id`. No OmniAuth, no passwords, no login page. The session layer (`User`, `Session`, `Membership`, `Authentication` concern) is auth-agnostic — OAuth providers can be re-added later by adding a new "front door" that calls `start_new_session_for`.

**Step 2: Run full suite one final time**

Run: `rake`
Expected: Lint clean, all tests pass.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note request.env pattern for trusted headers in CLAUDE.md"
```
