---
description: |
  Web 検索が必要な際に組み込みの WebSearch ツールではなく `gemini --prompt 'WebSearch: <query>'` を Task ツール経由で呼び出して Google Gemini CLI で検索する。ユーザーが gemini-search を明示的に指定したとき、または gemini を Web 検索バックエンドとして使いたいときに使う。
---

## Gemini Search

`gemini` is google gemini cli. **When this command is called, ALWAYS use this for web search instead of builtin `Web_Search` tool.**

When web search is needed, you MUST use `gemini --prompt` via Task Tool.

Run web search via Task Tool with `gemini --prompt 'WebSearch: <query>'`

Run

```bash
gemini --prompt "WebSearch: <query>"
```
