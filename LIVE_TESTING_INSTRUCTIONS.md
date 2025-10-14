# Live API Testing Instructions

## 🔍 Issues Found in Your Test

1. **Token not exported correctly** - Shell split it across multiple lines
2. **Auth not being passed to CLI** - Need to investigate why

---

## ✅ How to Set Token Correctly

### Option 1: Use Helper Script
```bash
source set_token_helper.sh
# Paste your token when prompted
# Token: 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
```

### Option 2: Manual Export (Single Line!)
```bash
export CLAUDE_AGENT_OAUTH_TOKEN='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'
```

**Important**: Use single quotes and keep on ONE LINE!

### Verify Token is Set
```bash
echo $CLAUDE_AGENT_OAUTH_TOKEN | head -c 30
# Should show: sk-ant-oat01-MvxhX-8pnRRnRsma
```

---

## 🧪 Run Live Tests

```bash
# Once token is set correctly:
mix run test_live_v0_1_0.exs
```

---

## 🔍 If Still Getting Auth Errors

The issue might be that the Claude CLI doesn't automatically use `CLAUDE_AGENT_OAUTH_TOKEN`.

**Let's test the CLI directly**:

```bash
# Test 1: Does CLI see the token?
claude --print "hello" --output-format json

# If you get auth error, try setting it as ANTHROPIC_API_KEY instead:
export ANTHROPIC_API_KEY="$CLAUDE_AGENT_OAUTH_TOKEN"
claude --print "hello" --output-format json
```

**Tell me which one works!**

---

## 🎯 Alternative: Use Existing Claude Login

If the OAuth token isn't working with environment variables:

```bash
# Use your existing claude login session
claude login  # If not already logged in

# Then test
mix run test_live_v0_1_0.exs
```

This should work because the CLI will use its stored session.

---

## 📝 What to Report Back

After testing, tell me:

1. **Which method worked?**
   - [ ] CLAUDE_AGENT_OAUTH_TOKEN env var
   - [ ] ANTHROPIC_API_KEY env var
   - [ ] Existing `claude login` session

2. **Test results?**
   - [ ] TEST 1 (Auth): PASS/FAIL
   - [ ] TEST 2 (Basic): PASS/FAIL
   - [ ] TEST 3 (Model): PASS/FAIL
   - [ ] TEST 4 (Agent): PASS/FAIL
   - [ ] TEST 5 (Parallel): PASS/FAIL
   - [ ] TEST 6 (Retry): PASS/FAIL

3. **Any errors?**
   - Copy/paste the error messages

4. **Total cost?**
   - How much did it cost?

---

I'll fix any authentication issues and get everything working properly!
