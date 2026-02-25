# Content Security Policy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Enable a strict `'self'`-only Content Security Policy header on all responses, closing GitHub issue #87.

**Architecture:** Replace the commented-out CSP initializer with an enforcing policy. All directives use `:self` except `connect-src` (adds `ws:` and `wss:` for ActionCable) and `object-src`/`frame-src` (set to `:none`). No nonces, no report-uri.

**Tech Stack:** Rails 8 CSP initializer (`config.content_security_policy`), Minitest integration test.

---

### Task 1: Write the failing integration test

**Files:**
- Create: `test/integration/content_security_policy_test.rb`

**Step 1: Write the test**

```ruby
# frozen_string_literal: true

require 'test_helper'

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'responses include Content-Security-Policy header' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_response :success
    csp = response.headers['Content-Security-Policy']
    assert csp, 'Expected Content-Security-Policy header to be present'

    assert_match(/default-src 'self'/, csp)
    assert_match(/script-src 'self'/, csp)
    assert_match(/style-src 'self'/, csp)
    assert_match(/connect-src 'self' ws: wss:/, csp)
    assert_match(/object-src 'none'/, csp)
    assert_match(/frame-src 'none'/, csp)
    assert_match(/base-uri 'self'/, csp)
    assert_match(/form-action 'self'/, csp)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/integration/content_security_policy_test.rb`
Expected: FAIL — `Content-Security-Policy` header is nil because the initializer is commented out.

---

### Task 2: Enable the CSP initializer

**Files:**
- Modify: `config/initializers/content_security_policy.rb`

**Step 1: Replace the file contents**

Replace the entire commented-out file with:

```ruby
# frozen_string_literal: true

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self
    policy.img_src     :self
    policy.font_src    :self
    policy.connect_src :self, 'ws:', 'wss:'
    policy.object_src  :none
    policy.frame_src   :none
    policy.base_uri    :self
    policy.form_action :self
  end
end
```

**Step 2: Run the integration test to verify it passes**

Run: `ruby -Itest test/integration/content_security_policy_test.rb`
Expected: PASS

**Step 3: Run the full test suite**

Run: `rake test`
Expected: All tests pass. The CSP header shouldn't break any existing tests since no views use inline scripts or styles.

**Step 4: Run lint**

Run: `rake lint`
Expected: No new offenses.

---

### Task 3: Commit and close the issue

**Step 1: Commit**

```bash
git add config/initializers/content_security_policy.rb test/integration/content_security_policy_test.rb
git commit -m "feat: enable Content Security Policy (closes #87)"
```
