# Hal Technical Brief: Summarizer Pipeline and SQLite Memory Schema
*For the Malcome team — prepared by the Hal project*

---

## 1. The Summarizer Pipeline

### High-Level Overview

Hal's summarizer exists to solve one problem: a 4096-token context window that would otherwise cap meaningful conversation length at roughly 10-15 turns. The summarizer compresses conversation history that has fallen outside the short-term memory (STM) verbatim window, producing a rolling prose summary that persists in the prompt on every subsequent turn until the next summarization cycle replaces it.

The pipeline has two stages: generation and verification. Generation produces a compressed prose narrative via an LLM call. Verification checks each sentence in that narrative against the source material and replaces any sentence that cannot be grounded back to the source.

### How It Compresses While Preserving Factual Integrity

Stage 1 uses a structured prompt that explicitly instructs the model to preserve factual claims, logical flow, key entities, relationships, and original intent — and explicitly prohibits adding interpretation or commentary. The prompt targets a specific token count, calculated from the available budget after STM and system prompt are accounted for.

Stage 2 runs a sentence-level verification pass. Each sentence in the generated summary is compared against the source sentences using NaturalLanguage sentence embeddings (NLEmbedding, cosine similarity). If a sentence's similarity to any source sentence falls below a threshold (default 0.55), it is replaced with the nearest-matching source sentence rather than kept. This prevents hallucinated details from surviving the summarization step. A TF-IDF fallback handles cases where NL embeddings are unavailable.

```swift
// Stage 1: Generate
static func summarize(
    text: String,
    targetTokens: Int,
    llmService: LLMService
) async -> String

// Stage 2: Verify each sentence against source
static func verifyNarrative(
    _ summary: String,
    against sourceSentences: [String],
    threshold: Double
) async -> String

// Public entry point — runs both stages
static func summarizeWithVerification(
    text: String,
    targetTokens: Int,
    llmService: LLMService
) async -> String
```

### Handling the 4K Token Constraint

AFM's 4096-token limit covers input and output combined. Apple does not expose a tokenizer, so Hal uses a heuristic of approximately 3-4 characters per token. Token estimation is conservative to avoid hitting the hard limit, which throws an unrecoverable error rather than truncating gracefully.

The prompt budget is allocated in priority order:

1. System prompt (fixed cost, injected every turn)
2. Self-knowledge entries (small, injected unconditionally)
3. STM verbatim turns (N most recent turns, user-configured)
4. Rolling summary (whatever fits after STM)
5. RAG snippets (whatever remains, subject to a separate max cap)
6. Response budget (reserved; Apple counts output tokens against the same window)

Summarization fires when `turnsSinceLastSummary >= memoryDepth`. It is now blocking: if summarization is due when the user sends a message, Hal completes the summary before building the prompt for the response. This prevents a race condition where the model responds before the new summary is available.

### Input and Output

Input to the summarizer is a contiguous block of conversation turns formatted as speaker-labeled prose:

```
User: My daughter Emma is 8 years old and loves astronomy.
Hal: That's wonderful — astronomy is a great way to develop curiosity about science.
User: She wants a telescope for her birthday.
```

Output is a compressed prose paragraph:

```
The user mentioned their 8-year-old daughter Emma, who loves astronomy and wants a 
telescope for her birthday.
```

The summary is stored in memory as `injectedSummary` (a published property on ChatViewModel) and injected into the prompt as a labeled section: `[SUMMARY OF EARLIER CONVERSATION]`.

### Hallucination Mitigation

Two mechanisms:

First, the generation prompt is written to be extractive rather than generative. It instructs the model to compress and preserve, not interpret or extend.

Second, the verification pass replaces any output sentence that cannot be semantically grounded to the source. This catches cases where the model elaborates beyond what was said. The replacement is always a verbatim source sentence, so the worst case is slightly awkward prose rather than a hallucinated fact.

A known limitation: the verification pass catches sentence-level hallucinations but not sub-sentence ones (e.g., "Emma is 9 years old" when the source said 8). This is a model quality ceiling, not an architectural gap.

### Key Design Decisions

**Blocking rather than fire-and-forget.** Earlier versions fired summarization as a detached Task after the response was sent. This caused the summary to be missing from the turn immediately following the trigger. Summarization now blocks the response, guaranteeing the summary is available before the prompt is built.

**Prose output, not structured extraction.** A structured fact-extraction approach was tested (extracting key-value pairs like `name: Emma, age: 8`). It was abandoned because small on-device models hallucinate structured output unreliably. Prose is lossier but more robust.

**Lossy by design.** The summarizer is not expected to capture every fact. It captures the shape and flow of the conversation. Specific facts that need to survive lossy compression are handled by RAG retrieval, not the summary.

---

## 2. The SQLite Memory Schema

### Table Structure

Hal uses SQLite with WAL mode. The core tables are:

**`unified_content`** — the primary RAG store. Every conversation turn, document chunk, and self-knowledge entry that should be semantically searchable lives here.

```sql
CREATE TABLE IF NOT EXISTS unified_content (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    embedding BLOB,                  -- NLEmbedding vector, 512 dimensions, Float32
    timestamp INTEGER NOT NULL,
    source_type TEXT NOT NULL,       -- 'conversation', 'document', 'self_knowledge'
    source_id TEXT NOT NULL,         -- conversationId or documentId
    position INTEGER NOT NULL,       -- turn ordering within a source
    is_from_user INTEGER,            -- 1 = user, 0 = assistant, NULL = document
    entity_keywords TEXT,            -- NL-extracted entities, pipe-delimited
    recorded_by_model TEXT,          -- which model generated this content
    metadata_json TEXT,
    device_type TEXT,
    turn_number INTEGER NULL,
    deliberation_round INTEGER NULL,
    seat_number INTEGER NULL
);
```

**`sources`** — one row per document or conversation source, used for deduplication and metadata.

```sql
CREATE TABLE IF NOT EXISTS sources (
    id TEXT PRIMARY KEY,
    source_type TEXT NOT NULL,       -- 'document', 'conversation'
    display_name TEXT NOT NULL,
    file_path TEXT,
    url TEXT,
    created_at INTEGER NOT NULL,
    last_updated INTEGER NOT NULL,
    total_chunks INTEGER DEFAULT 0,
    content_hash TEXT,               -- for change detection on re-ingestion
    file_size INTEGER DEFAULT 0
);
```

**`self_knowledge`** — Hal's accumulated self-knowledge, confidence-weighted and decay-eligible.

```sql
CREATE TABLE IF NOT EXISTS self_knowledge (
    id TEXT PRIMARY KEY,
    category TEXT NOT NULL,          -- 'preference', 'value', 'behavior_pattern', 'reflection'
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    confidence REAL DEFAULT 0.5,     -- 0.0-1.0
    source_turn_range TEXT,
    reinforcement_count INTEGER DEFAULT 0,
    last_reinforced INTEGER NOT NULL,
    reflection_log TEXT,
    shareable INTEGER DEFAULT 0,
    device_id TEXT,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    UNIQUE(category, key)
);
```

**`threads`** — one row per conversation thread.

```sql
CREATE TABLE IF NOT EXISTS threads (
    id TEXT PRIMARY KEY,             -- conversationId (UUID)
    title TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_active_at INTEGER NOT NULL,
    title_is_user_set INTEGER DEFAULT 0,
    sort_order INTEGER DEFAULT 0
);
```

**`conversation_artifacts`** — full verbatim conversation history, never RAG-eligible, used for transparency and reconstruction only.

### How Memories Are Written

Every conversation turn is written to `unified_content` via `storeTurn()` after the response is complete. The write path:

1. Generate NLEmbedding vector for the content (512-dimensional Float32, stored as BLOB)
2. Extract named entities using NLTagger (people, places, organizations), stored pipe-delimited in `entity_keywords`
3. Write row with `source_type = 'conversation'`, `source_id = conversationId`, `turn_number`, `is_from_user`
4. Write to `conversation_artifacts` for verbatim record

Documents are chunked (typically 500-1000 character chunks with overlap) and each chunk written as a separate `unified_content` row with `source_type = 'document'`.

### How Memories Are Retrieved

Retrieval is a two-path hybrid: semantic search and entity/keyword search.

**Semantic path:** The query text is embedded using NLEmbedding. Cosine similarity is computed against all stored embeddings. A recency decay factor is applied: `adjustedScore = semanticScore * (recencyWeight * recencyScore + (1 - recencyWeight))`. Recency uses a half-life formula with configurable half-life (default 90 days) and a floor (default 0.15) so old memories never drop to zero.

**Entity path:** NLTagger extracts entities from the query. These are used to construct SQL LIKE clauses against `entity_keywords`. Keyword matches receive a fixed relevance score (0.60) regardless of semantic similarity — below the typical semantic threshold but high enough to surface exact entity matches that embedding similarity might miss.

Results from both paths are merged, de-duplicated, and filtered by a minimum relevance threshold (default 0.75, user-configurable). STM turns (currently in the verbatim window) are excluded by `turn_number NOT IN (...)` to avoid retrieving what is already in the prompt verbatim.

A RAG gate fires before retrieval: a lightweight LLM call asks whether the question requires stored facts beyond what is already in the current STM and summary. If the gate returns NO, retrieval is skipped entirely.

Cosine deduplication runs after retrieval: each RAG snippet is compared against the concatenated STM and summary text. Snippets with similarity above a threshold (default 0.85) are dropped before injection.

### How Memory Integrates with the LLM Call

The prompt is assembled in labeled sections:

```
[SYSTEM PROMPT]
...

[SUMMARY OF EARLIER CONVERSATION]
...rolling summary...

[RELEVANT MEMORIES]
[1] conversation | Relevance: 0.89
The user mentioned their daughter Emma loves astronomy.

[2] document | Relevance: 0.82
...

[RECENT CONVERSATION]
User: ...
Hal: ...
User: (current message)
```

The injection order reflects priority: summary before RAG, RAG before STM, STM last so the model reads the current conversation immediately before generating a response.

### How It Handles Context Window Pressure

When the total token estimate approaches the 4096 limit:

1. RAG snippets that exceed a per-snippet token budget are summarized inline using `TextSummarizer.summarizeWithVerification()` before injection
2. The total RAG budget is capped (user-configurable, default varies by model)
3. If a snippet cannot fit even summarized, it is dropped
4. STM depth is clamped by `maxMemoryDepth` (computed as `contextWindow / 400`, minimum 5), preventing the user from setting an STM window that leaves no room for anything else

The hard limit is never approached intentionally. The system is designed to stay below 80% of the context window to leave headroom for the response.

### Key Design Decisions

**One unified table for all retrievable content.** Conversations, documents, and self-knowledge are all in `unified_content`. This means a single RAG query searches everything. The `source_type` column allows filtering when needed.

**Embeddings stored as BLOBs.** NLEmbedding vectors are computed at write time and stored. Retrieval reads stored vectors rather than re-embedding, which is faster and avoids re-embedding cost on every query.

**Recency decay, not deletion.** Old memories are not expired or deleted. Their relevance score decays over time. This means the system degrades gracefully — old facts can still surface if no newer information is more relevant — rather than hard-forgetting at an arbitrary cutoff.

**Entity extraction as a parallel retrieval path.** Semantic similarity misses exact proper noun matches (the Labrador Problem: "dog" doesn't retrieve "Labrador"). Entity extraction and keyword search handle the cases embeddings miss.

---

## What We Would Do Differently Starting Fresh

**Token estimation.** Apple does not expose a tokenizer. The character-based heuristic (3-4 chars/token) works but is imprecise, especially for non-English text, code, and emoji. iOS 26.4 introduces a `contextSize` property and token usage tracking — a fresh implementation should use that API rather than heuristics.

**Ingestion-time semantic type normalization.** Entity extraction stores raw entities ("Labrador") but not semantic types ("pet/dog"). A small static taxonomy at ingest time would make entity retrieval significantly more powerful without changing the retrieval architecture.

**Embedding model.** NLEmbedding is convenient but not state of the art. For Malcome's cultural signal use case, where nuanced semantic similarity matters, it's worth evaluating whether a more capable on-device embedding model is available or can be bundled.

**RAG gate prompt calibration.** The gate LLM call that decides whether to run retrieval is prone to false negatives on personal questions phrased as general inquiries ("do you know anything about my sister?"). The gate prompt needs explicit framing around personal and relational context, not just factual lookup.

**Summary persistence.** The rolling summary should be injected on every turn between summarization cycles, not just the turn it fires. An early implementation injected it only once (the turn summarization completed), leaving a gap where facts were neither in STM nor in the summary. The fix is simple: inject whenever `injectedSummary` is non-empty, not only when `pendingAutoInject` is true.

---

*Prepared for the Malcome team from the Hal Universal project.*
*Source code: github.com/markfriedlander/Hal-Universal*
