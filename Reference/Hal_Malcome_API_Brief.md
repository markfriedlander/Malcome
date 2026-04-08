# Hal Technical Brief: Local API and Test Runner
*For the Malcome team — voice prompt iteration workflow*

---

## 1. The Local API

### What's Happening Under the Hood

When you toggle the Developer API on in Hal's settings, a `LocalAPIServer` instance starts an `NWListener` bound to port 8765 on all network interfaces (not just localhost). This means the server is reachable from any device on the same local network — your Mac's terminal can reach Hal running on an iPhone over WiFi, or reach Hal running as a Mac Catalyst app on the same machine.

The Bearer token is generated once on first launch using `SecRandomCopyBytes`, stored in the iOS Keychain, and persisted across app restarts. It is displayed in settings so you can copy it for use in curl or the Python test runner. Every inbound request is validated against this token before any processing occurs. A missing or incorrect token returns HTTP 401 with no further information.

The server shuts down cleanly when you toggle it off. It does not start unless explicitly enabled by the user — important for App Store compliance and user trust.

### Available Endpoints

**POST /chat**

Sends a message through the full Hal pipeline — system prompt, STM, rolling summary, RAG gate, retrieval, dedup, response generation — exactly as if the user had typed it in the UI. The call blocks until Hal's response is complete.

Request:
```json
{ "message": "What do you know about coral reefs?" }
```

Response:
```json
{
  "response": "Coral reefs are...",
  "conversationId": "abc-123",
  "turnNumber": 4,
  "inferenceSeconds": 2.3
}
```

**POST /command**

Executes a harness command against the running app state. Same command set as the file-based test console. Does not generate an AI response — pure app control.

Request:
```json
{ "command": "NEW_THREAD" }
```

Available commands:
- `NEW_THREAD` — start a fresh conversation, preserve memory DB
- `RESET_THREAD` — delete current thread and start fresh
- `SET_SYSTEM_PROMPT:<text>` — override the system prompt for this session (non-persistent, reverts on restart)
- `CLEAR_SYSTEM_PROMPT` — remove the override, revert to stored prompt
- `SET_MEMORY_DEPTH:<n>` — set STM window depth
- `GET_STATE` — returns current state JSON (same as GET /state)
- `CLEAR_TEST_DATA` — wipe conversation data from DB for clean testing

Response:
```json
{ "status": "ok", "command": "NEW_THREAD" }
```

**GET /state**

Returns a snapshot of current app state — no AI call involved.

Response includes: `conversationId`, `memoryDepth`, `lastSummarizedTurnCount`, `activeModel`, `messageCount`, `injectedSummary` (truncated), `pendingAutoInject`.

---

### Curl Examples

**Send a message:**
```bash
curl -s -X POST http://<HAL_IP>:8765/chat \
  -H "Authorization: Bearer <YOUR_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"message": "Describe yourself in one sentence."}' \
  | python3 -m json.tool
```

**Set a system prompt:**
```bash
curl -s -X POST http://<HAL_IP>:8765/command \
  -H "Authorization: Bearer <YOUR_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"command": "SET_SYSTEM_PROMPT:You are a concise cultural signal detector. Respond in plain prose, never lists."}'
```

**Start a fresh conversation:**
```bash
curl -s -X POST http://<HAL_IP>:8765/command \
  -H "Authorization: Bearer <YOUR_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"command": "NEW_THREAD"}'
```

**Check current state:**
```bash
curl -s -X GET http://<HAL_IP>:8765/state \
  -H "Authorization: Bearer <YOUR_TOKEN>" \
  | python3 -m json.tool
```

---

### Python Examples

```python
import http.client
import json

HAL_IP = "192.168.x.x"   # Hal device IP from settings screen
HAL_PORT = 8765
TOKEN = "your-token-here"

def hal_request(method, path, body=None):
    conn = http.client.HTTPConnection(HAL_IP, HAL_PORT, timeout=120)
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json"
    }
    payload = json.dumps(body).encode() if body else None
    conn.request(method, path, payload, headers)
    resp = conn.getresponse()
    return json.loads(resp.read())

# Send a message
result = hal_request("POST", "/chat", {"message": "What trends did you notice last week?"})
print(result["response"])

# Set system prompt
hal_request("POST", "/command", {"command": "SET_SYSTEM_PROMPT:You are a voice assistant. Be brief."})

# Fresh conversation
hal_request("POST", "/command", {"command": "NEW_THREAD"})

# Get state
state = hal_request("GET", "/state")
print(state)
```

---

## 2. The Python Test Script (hal_test.py)

### What `setup` Does

```bash
python3 tests/hal_test.py setup 192.168.x.x 8765 <token>
```

Writes a config file to `tests/.hal_api_config.json` containing the IP, port, and token. All subsequent commands read from this file — you never re-enter credentials. The script then verifies connectivity by calling GET /state and prints the current app state.

### Sending a Message

```bash
python3 tests/hal_test.py chat
```

Opens an interactive REPL. You type a message, the script POSTs it to /chat, blocks until Hal responds, prints the response, and waits for your next input. Each response is also written to `tests/last_output.json` for inspection.

For scripted single-turn use:

```bash
python3 tests/hal_test.py turn "What cultural signals emerged from last week's data?"
```

### The output_latest.json Fields

Every turn — whether sent via the file-based console or the HTTP API — writes a full diagnostic JSON. The fields most useful for voice prompt iteration:

```json
{
  "turn": 3,
  "elapsed": 2.14,
  "userMessage": "What trends did you notice?",
  "response": "Three themes emerged...",

  "sectionsInjected": ["system", "short_term_memory", "summary", "rag"],

  "tokenBreakdown": {
    "system": 312,
    "shortTerm": 580,
    "summary": 140,
    "rag": 210,
    "userInput": 18,
    "completion": 95,
    "totalPrompt": 1260,
    "total": 1355,
    "contextWindow": 4096,
    "percentUsed": 33.1
  },

  "memoryRetrieved": [
    {
      "content": "User mentioned coral reef signal from Tuesday...",
      "relevance": 0.87,
      "source": "conversation",
      "isEntityMatch": false
    }
  ],

  "fullPromptUsed": "...the complete raw prompt string sent to AFM..."
}
```

**For voice prompt iteration, focus on:**

- `sectionsInjected` — tells you which memory layers fired. If `rag` is absent, the gate said NO. If `summary` is absent between summarization cycles, that's the summary persistence bug (check that `injectedSummary` is non-empty in GET /state).
- `tokenBreakdown.percentUsed` — if this is consistently above 70%, your prompt or memory depth is too aggressive for AFM's 4096-token window.
- `fullPromptUsed` — the ground truth. Paste this into a text editor to see exactly what AFM received. For voice prompt tuning, this is more useful than any diagnostic — it shows whether your system prompt is being constructed the way you intended.
- `memoryRetrieved` — shows what RAG surfaced and at what relevance scores. If the gate fires but nothing relevant comes back, the issue is retrieval quality, not the gate.

---

## 3. App Control Available Through the API

Everything relevant to voice prompt iteration is accessible without a build cycle:

| Command | What it does |
|---|---|
| `SET_SYSTEM_PROMPT:<text>` | Replace the active system prompt. Takes effect on the next turn. Non-persistent — reverts on app restart. |
| `CLEAR_SYSTEM_PROMPT` | Restore the stored system prompt. |
| `NEW_THREAD` | Start a fresh conversation. Memory DB preserved — cross-session RAG still works. |
| `RESET_THREAD` | Delete current thread and start fresh. Use when you want no STM contamination from prior turns. |
| `CLEAR_TEST_DATA` | Wipe conversation data from the DB entirely. Use for a completely clean baseline test. |
| `SET_MEMORY_DEPTH:<n>` | Change STM window size. Useful for testing how much context AFM uses before summarization kicks in. |
| `GET_STATE` | Inspect current conversationId, memory depth, summarization state, active model. |

**What you cannot control via API** (requires a build): persistent system prompt changes, temperature, RAG similarity threshold, recency weight. These live in AppStorage and require the settings UI or a direct UserDefaults write. For iterating on the voice prompt specifically, `SET_SYSTEM_PROMPT` covers everything you need without a build.

---

## 4. Recommended Workflow for Voice Prompt Iteration

The fastest loop:

**Step 1 — Baseline**
```bash
python3 tests/hal_test.py setup <IP> 8765 <token>
curl ... POST /command {"command": "CLEAR_TEST_DATA"}
curl ... POST /command {"command": "SET_SYSTEM_PROMPT:<your prompt v1>"}
```

**Step 2 — Test turn**
```bash
python3 tests/hal_test.py turn "Your test message here"
```

Read the response. Open `output_latest.json`. Check `fullPromptUsed` to verify your prompt landed correctly. Check `tokenBreakdown.percentUsed` to ensure you have headroom.

**Step 3 — Iterate**
```bash
curl ... POST /command {"command": "NEW_THREAD"}
curl ... POST /command {"command": "SET_SYSTEM_PROMPT:<your prompt v2>"}
python3 tests/hal_test.py turn "Same test message"
```

`NEW_THREAD` between iterations prevents STM from the previous test contaminating the next one. `CLEAR_TEST_DATA` between major revisions if you want RAG completely clean.

**For multi-turn voice flow testing:**
```bash
python3 tests/hal_test.py chat
```

Type your turns interactively. After each one, `cat tests/last_output.json | python3 -m json.tool` in a second terminal to see the full diagnostic without interrupting the conversation.

**The key principle:** `fullPromptUsed` in the output JSON is your ground truth. AFM is a black box — the only way to know what it actually received is to read that field. For voice prompt work, build the habit of checking it on every iteration rather than assuming the prompt was constructed as intended.

---

*Prepared for the Malcome team from the Hal Universal project.*
*Source code: github.com/markfriedlander/Hal-Universal*
