#!/usr/bin/env python3
"""Generate example sentences for the top N most frequent characters.

Usage:
  tool/venv/bin/python tool/gen_sentences.py          # top 1000 chars
  tool/venv/bin/python tool/gen_sentences.py 500      # top 500 chars

Requires ANTHROPIC_API_KEY in the environment.
Progress is saved after every word, so the script is safe to interrupt
and resume.
"""

import gzip
import json
import sys
import time
from pathlib import Path

import anthropic
import jieba

REPO = Path(__file__).parent.parent
FREQ_FILE = REPO / "assets" / "word_freq.tsv.gz"
OUTPUT_FILE = REPO / "assets" / "example_sentences.json"

TOP_N = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
SENTENCES_PER_WORD = 5
SAVE_EVERY = 10          # words between saves
RETRY_LIMIT = 3
RETRY_DELAY = 5.0        # seconds between retries

METAPROMPT = """\
Generate {n} example sentences for the Chinese word/character "{word}" \
for a learner dictionary app.
Levels 1–3 must be genuinely easy; levels 4–5 are intermediate-to-advanced \
but never literary.

LEVEL CONSTRAINTS
Level 1 — HSK1 vocabulary only. Simple SVO. ≤8 characters. \
Concrete topics (food, family, place).
Level 2 — HSK1–2 vocabulary. May add a time word or simple modifier. \
≤12 characters.
Level 3 — HSK2–3 vocabulary. May use 虽然/但是, 因为/所以, 的时候. \
≤16 characters.
Level 4 — HSK3–4 vocabulary. One subordinate clause or contrast. \
≤22 characters. No archaic language.
Level 5 — HSK4–5 vocabulary. Natural adult speech; common 成语 are fine. \
≤28 characters.

HARD RULES
- "{word}" must appear naturally in every sentence — never forced.
- No classical, poetic, or archaic language at any level.
- No proper nouns unless they are HSK vocabulary.
- Pinyin uses tone marks (ā á ǎ à), not numbers.
- English must be natural spoken English, not a word-for-word gloss.

OUTPUT: a JSON array of exactly {n} objects, no other text:
[{{"level": 1, "zh": "...", "pinyin": "...", "en": "..."}}, ...]"""


def load_top_words(n: int) -> list[str]:
    words = []
    with gzip.open(FREQ_FILE, "rt", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) == 2:
                words.append(parts[1])
            if len(words) >= n:
                break
    return words


def load_existing() -> dict[str, list[dict]]:
    if not OUTPUT_FILE.exists():
        return {}
    data = json.loads(OUTPUT_FILE.read_text(encoding="utf-8"))
    by_word: dict[str, list[dict]] = {}
    for s in data:
        by_word.setdefault(s["targetWord"], []).append(s)
    return by_word


def save(by_word: dict[str, list[dict]]) -> None:
    flat = [s for sentences in by_word.values() for s in sentences]
    OUTPUT_FILE.write_text(
        json.dumps(flat, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def generate_for_word(
    client: anthropic.Anthropic, word: str
) -> list[dict]:
    prompt = METAPROMPT.format(word=word, n=SENTENCES_PER_WORD)
    for attempt in range(1, RETRY_LIMIT + 1):
        try:
            msg = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=1024,
                messages=[{"role": "user", "content": prompt}],
            )
            text = msg.content[0].text.strip()
            start = text.find("[")
            end = text.rfind("]") + 1
            if start == -1 or end == 0:
                raise ValueError("No JSON array found in response")
            sentences = json.loads(text[start:end])
            if not isinstance(sentences, list) or len(sentences) == 0:
                raise ValueError("Empty or invalid sentence list")
            result = []
            for s in sentences:
                segments = jieba.lcut(s["zh"])
                result.append({"targetWord": word, **s, "segments": segments})
            return result
        except Exception as exc:
            if attempt == RETRY_LIMIT:
                raise
            print(f" (retry {attempt}: {exc})", end="", flush=True)
            time.sleep(RETRY_DELAY)
    raise RuntimeError("unreachable")


def main() -> None:
    words = load_top_words(TOP_N)
    existing = load_existing()

    to_generate = [w for w in words if w not in existing]
    total = len(to_generate)
    already = len(existing)
    print(
        f"Top {TOP_N} words — {already} already done, {total} to generate."
    )
    if total == 0:
        print("Nothing to do.")
        return

    client = anthropic.Anthropic()

    errors: list[str] = []
    for i, word in enumerate(to_generate, 1):
        print(f"[{i:4d}/{total}] {word!r:8s}", end=" ", flush=True)
        try:
            sentences = generate_for_word(client, word)
            existing[word] = sentences
            print(f"✓ {len(sentences)} sentences")
        except Exception as exc:
            print(f"✗ FAILED: {exc}")
            errors.append(word)
            continue

        if i % SAVE_EVERY == 0 or i == total:
            save(existing)
            n_sentences = sum(len(v) for v in existing.values())
            print(f"  → saved ({n_sentences} sentences for {len(existing)} words)")

    save(existing)
    n_sentences = sum(len(v) for v in existing.values())
    print(f"\nDone. {n_sentences} sentences for {len(existing)} words.")
    if errors:
        print(f"Failed words ({len(errors)}): {', '.join(errors)}")


if __name__ == "__main__":
    main()
