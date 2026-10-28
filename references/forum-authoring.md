# Forum Authoring — Markdown, Drafts and the Immutable Slug

Everything an agent needs to author HOT forum posts without corrupting them. The authoritative
implementations are `packages/mcp-server/src/tools/forum.ts` (tool surface) and
`packages/shared/src/forum-markdown.ts` (the converter) — everything below is derived from them.

Tool-by-tool parameters live in [tool-catalog.md → Forum Tools](tool-catalog.md#forum-tools).
A full worked flow lives in [examples/10-forum-post-publish.md](../examples/10-forum-post-publish.md).

---

## The one rule everything else follows from

**The forum stores post content as BlockNote JSONB (`forum_posts.content`). The MCP tool surface never
exposes it.** Content goes in as Markdown (`content_markdown` / `append_markdown`) and comes out as
Markdown (`content_markdown`). There is no tool parameter anywhere that accepts BlockNote JSON, and
there is no DB-level schema that would catch a hallucinated block type — `content` is JSONB, so a bad
shape is stored happily and breaks the web renderer instead.

So: **write Markdown, read Markdown, and never try to hand-build blocks.**

---

## Supported Markdown subset (inbound: `content_markdown` / `append_markdown`)

Parsing is `unified` + `remark-parse` + `remark-gfm` (CommonMark + GFM), mapped onto `@blocknote/core`'s
**default** schema only — the same schema `components/forum/forum-editor.tsx` uses. There are no custom
blocks in the forum.

| Markdown you write | Becomes | Notes |
|---|---|---|
| `# …` through `###### …`, and setext (`Title` + `=====`) | `heading`, `props.level` 1–6 | Depth clamped to 1–6 |
| Plain paragraph | `paragraph` | |
| `**bold**` | `bold` style | |
| `*italic*` / `_italic_` | `italic` style | |
| `~~strike~~` | `strike` style | GFM |
| `` `code` `` | `code` style | Backtick run auto-widened on the way back out |
| `[text](url)` | `link` inline | Only **text** children survive inside a link (see "Dropped" below) |
| `<https://x>` and bare `https://x` | `link` inline | GFM autolink literal — both work |
| `- ` / `* ` | `bulletListItem` | |
| `1. ` | `numberedListItem` | A list not starting at 1 puts `props.start` on its **first** item only |
| `- [x]` / `- [ ]` | `checkListItem`, `props.checked` | GFM task list |
| Indented sub-lists | `children`, up to depth 6 | Deeper content is flattened — warns `max_depth_exceeded` |
| ```` ```ts … ``` ```` | `codeBlock`, `props.language` | No info string → `language: "text"` |
| `> quote` | `quote` | **Only the first paragraph** becomes the quote |
| `---` / `***` / `___` (not on line 1) | `divider` | On line 1 it's treated as frontmatter → hard error |
| GFM table | `table`, `headerRows: 1` | Column alignment is dropped (see below) |
| `![alt](url)` **alone** in its own paragraph | `image` block, `props.caption` = `props.name` = alt | |
| Two trailing spaces + newline | a `\n` inside the text span | Round-trips back as two trailing spaces |

Everything in that table survives a Markdown → BlockNote → Markdown round trip essentially unchanged.

### What the converter never produces

`markdownToBlockNote` **never** emits `toggleListItem`, `video`, `audio`, `file` or `pageBreak` — Markdown
has no source syntax for any of them. It also never emits `underline`, `textColor`, `backgroundColor` or
`textAlignment`, for the same reason. Those block/style kinds can only arrive via the web editor, which
is exactly why reading them back out is lossy.

---

## Dropped or degraded on the way in — and the warning code you'll see

Every write tool returns `conversion: { blocks_created, warnings }`. Read it. A `warnings` array is the
converter telling you your Markdown did not fully land.

| What you wrote | What actually happened | Warning `code` |
|---|---|---|
| HTML block (`<div>…</div>`) | Block dropped entirely | `html_dropped` |
| Inline HTML (`a <b>bold</b> c`) | Tags dropped, the text between them survives → `a bold c` | `html_dropped` (one per tag) |
| Footnote reference `[^1]` | Dropped | `footnote_dropped` |
| Footnote definition `[^1]: …` | Dropped | `footnote_dropped` |
| Link-reference definition `[d]: https://x` | Dropped | `definition_dropped` |
| **Reference-style link usage `[docs][d]`** | **The link text disappears too** — `See [docs][d].` becomes `See .` | `unsupported_markdown_node` (`"linkReference"`) |
| Image inline with other text (`text ![a](u) more`) | Becomes a text link `[a](u)` | `inline_image_to_link` |
| Blockquote with 2+ paragraphs | First paragraph → `quote`; the rest become **sibling paragraphs after it**, outside the quote | `blockquote_multi_paragraph` |
| Nesting deeper than 6 levels | Hoisted next to its parent instead of nesting further | `max_depth_exceeded` |
| Any other mdast node type | Dropped | `unsupported_markdown_node` |
| Table column alignment (`\|:--\|--:\|`) | Silently dropped — all columns render default-aligned | **none** |

> **Use inline links, not reference links.** `[docs][d]` is the single worst case in this table: it is
> the only construct where the *visible text* vanishes, not just the formatting. Always write
> `[docs](https://…)`.

### Hard failures — the call throws and nothing is written

| Condition | Error |
|---|---|
| First line of the Markdown is `---` | `El Markdown comienza con un bloque de frontmatter ("---" en la primera línea), que no está soportado: se confundiría con un divisor horizontal. Elimina el frontmatter antes de convertir.` |
| The Markdown expands to more than 2000 blocks (nested children counted) | `El Markdown genera N bloques, por encima del límite de 2000. Reduce el contenido antes de guardarlo.` |
| `content_markdown` / `append_markdown` longer than 100 000 chars, or empty | Zod rejects it at the tool boundary |

Strip frontmatter before you send. If you want a horizontal rule at the very top of a post, put a line
of text above it.

---

## Reading it back: `content_conversion.lossy`

`get_forum_post` returns the post's content as Markdown plus:

```json
"content_conversion": {
  "lossy": true,
  "dropped_block_types": ["video", "toggleListItem"],
  "warnings": [{ "code": "underline_dropped", "message": "…" }]
}
```

`lossy: true` means **the Markdown you are holding is a degraded view of the stored post.** The real
content has formatting Markdown cannot express. What triggers it:

| Stored in BlockNote | What the Markdown shows | Warning `code` | In `dropped_block_types` |
|---|---|---|---|
| `textColor` prop or style ≠ `"default"` | colour gone | `text_color_dropped` | — |
| `backgroundColor` prop or style ≠ `"default"` | highlight gone | `background_color_dropped` | — |
| `textAlignment` prop ≠ `"left"` | centring/justification gone | `text_alignment_dropped` | — |
| `underline` style | underline gone | `underline_dropped` | — |
| `video` / `audio` / `file` block | `[name](url)` text link | `video_downgraded` / `audio_downgraded` / `file_downgraded` | yes |
| `pageBreak` | `---` | `page_break_downgraded` | yes |
| `toggleListItem` | `- item` (plain bullet, children indented under it) | `toggle_list_item_downgraded` | yes |
| Table with >1 header row, or any header column | Flattened to a single header row | `table_structure_flattened` | — |
| Table cell with `colspan`/`rowspan` > 1 | Spans ignored | `table_span_flattened` | — |
| Any unknown block type | `<!-- bloque no soportado: X -->` | `unsupported_block_type` | yes |

`lossy: false` with an empty `warnings` array means the Markdown is a faithful representation and you can
treat it as the source of truth.

**Cosmetic differences are not losses.** Top-level blocks are re-joined with a blank line between them,
so a tight list you wrote as

```markdown
- one
- two
```

comes back as

```markdown
- one

- two
```

Same blocks, same render. Don't "fix" it — and in particular don't re-send the whole body just to close
the gap, because a full replace is the one operation that *does* destroy content.

---

## `append_markdown` vs `content_markdown` — pick the right one

| | `content_markdown` | `append_markdown` |
|---|---|---|
| Effect | **Replaces** `forum_posts.content` wholesale | Converts only the new text and concatenates its blocks after the existing ones |
| Safe when | `content_conversion.lossy` was `false`, **or** you genuinely intend to rewrite the post | Always |
| Use for | A real rewrite the user asked for | Adding a section, a paragraph, a note, an update |
| Mutually exclusive | Passing both → `content_markdown y append_markdown son mutuamente excluyentes: usa solo uno por llamada.` | same |

**The rule**: if the last `get_forum_post` reported `content_conversion.lossy: true`, **use
`append_markdown`.** Sending the lossy Markdown back as `content_markdown` is a silent, irreversible
downgrade — the colours, the alignment, the underline, the embedded video are all gone from the stored
blocks, and there is no undo.

Even when `lossy` is `false`, `append_markdown` is the better default for additive edits: one call, no
risk of a transcription mistake in the parts you didn't mean to touch.

**Both overwrite `excerpt`** with an auto-generated one
(the post's plain text truncated to 300 chars) unless you pass `excerpt` explicitly **in that same
call**. A hand-written excerpt does not survive a content edit on its own — re-send it. An explicit
`excerpt` always wins, including an explicit `null`, which clears it.

(Both also recompute `reading_time_minutes` from `extractTextFromBlocks`, which reads only `text`
inlines — link labels and table cells don't count toward it. The reading time is an estimate, not a
measurement; don't chase small discrepancies.)

---

## The slug never changes

`generateSlug(title)` runs **only** inside `create_forum_post` (slugified title, truncated to 80 chars,
plus a 4-char random suffix; up to 3 attempts on a unique-violation). `update_forum_post` never touches
`slug`, **even when you change the `title`** — and that is deliberate, not an oversight:

- `/foro/{slug}` is the public URL people have already shared and bookmarked.
- `notifications.entity_id` stores the **slug**, not the post id (`lib/forum-notifications.ts`), and
  `getNotificationUrl` builds `/foro/{entity_id}`. Regenerating the slug would 404 every notification
  already sent for that post.

So after a title change, keep using the original slug (or just use `id`, which never changes either).
Every forum tool that resolves a post accepts `id` **or** `slug` — exactly one, never both and never
neither, or you get `Debes proporcionar exactamente uno de id/slug.`

> There is a known divergence in the web app: `updateForumPost` in `lib/services/requests.ts` *does*
> regenerate the slug on a title change. That's a bug tracked on the web side. The MCP tools do not
> replicate it — do not "fix" the MCP side to match.

---

## Draft → published, and nothing in between

`create_forum_post` defaults to **`status: "draft"`**. That is on purpose: you have just run text through
a lossy-capable converter, and nobody has looked at the result yet.

```
create_forum_post(title, content_markdown)            → draft, returns id + slug + conversion.warnings
get_forum_post(slug)                                   → read content_markdown back, check it renders as intended
update_forum_post(slug, append_markdown: "…")          → fix/extend if needed
update_forum_post(slug, status: "published")           → now it's live, notifications fire
```

**There are no `publish_forum_post` / `unpublish_forum_post` tools.** `update_forum_post(status:)`
absorbs both:

- `status: "published"` sets `published_at` **only if it was never set before**. Republishing a post that
  was unpublished keeps its original publish date — the recency bonus in `popularity_score` isn't
  resettable by a toggle.
- `status: "draft"` clears `published_at` (`null`), same as the web app's unpublish action.
- `notifications_dispatched` in the response is `true` only for a genuine `draft → published` transition.
  Re-sending `status: "published"` on an already-published post dispatches nothing.

Also worth knowing: `notifications_dispatched: false` does **not** mean the publish failed. The
notification hop is fire-and-log (`notifyForumEvent`) — the post is already committed by the time it
runs, and a missing `HOT_APP_URL`/`INTERNAL_API_SECRET`, a timeout, or a non-2xx all come back as
`false` without throwing.

### Who can do what — the asymmetry that looks like a bug

Authorization in `forum.ts` is a **literal** replica of the RLS policies in
`supabase/migrations/00039_forum_module.sql`, including their inconsistencies:

| Operation | Policy | Who |
|---|---|---|
| Read (`list_forum_posts`, `get_forum_post`) | `forum_posts_select_published_or_own` — **no admin branch** | Published posts: anyone. Drafts: **the author only** |
| Create (`create_forum_post`) | `forum_posts_insert_admin_developer` | `admin` and `developer` only — `designer`/`commercial` get `No tienes permiso para publicar en el foro. Solo administradores y desarrolladores pueden crear publicaciones.` |
| Update / delete | `forum_posts_update_author_or_admin` / `_delete_author_or_admin` — **has an admin branch** | Author **or** any admin |

Read that table twice. **An admin cannot read another author's draft, but can publish or delete it.**
Two different policies, two different rules, faithfully copied. `get_forum_post` on someone else's draft
returns `Post no encontrado o no tienes permiso para verlo.` — the same message as a nonexistent id, on
purpose, so ids can't be enumerated by diffing errors. That is **not** the tool being broken; don't retry
it, don't report it as a bug, and don't try to work around it. If an admin needs to review a draft, the
author has to publish it or paste it.

The same floor applies to listing: `list_forum_posts` always ORs in `status.eq.published,author_id.eq.<you>`
regardless of your other filters, and asking for `status: "draft"` or `"all"` without being self-scoped
(`tab: "mine"`, or `author_id` equal to your own id) silently coerces the filter to `published` and sets
`status_filter_coerced: true` in the response. Check that flag before concluding "there are no drafts."

---

## Categories are read-only through MCP

There is **no** `create_forum_category` and no delete. The taxonomy is curated by humans in the app.
`list_forum_categories` is the whole category surface, and it returns `post_count` per category so you
can see which ones are actually in use instead of guessing:

```
list_forum_categories()
→ { "total": 4, "categories": [
    { "id": "…", "name": "Anuncios",  "color": "#f97316", "icon": "megaphone", "post_count": 12 },
    { "id": "…", "name": "Tutoriales","color": "#22c55e", "icon": "book",      "post_count": 3  },
    …
  ]}
```

`create_forum_post`/`update_forum_post` take `category_ids` (UUIDs, max 5). `create_forum_post` also
takes `category_names`, matched **case-insensitively**. An unknown name does not get created and does not
get ignored — it throws, listing the real options:

```
No existen las categorías: Novedades. Categorías válidas: Anuncios, Debate, Preguntas, Tutoriales.
```

That error is the only guardrail against a hallucinated category, so treat it as a prompt to call
`list_forum_categories`, not as something to retry with a different guess.

Two asymmetries to remember:

- `update_forum_post` takes **`category_ids` only** — no `category_names`. Resolve names to UUIDs with
  `list_forum_categories` first.
- `category_ids` on `update_forum_post` **replaces the post's whole category list** (delete-then-insert).
  Passing one id drops the others; passing `[]` removes them all. Always send the complete intended set.

On `list_forum_posts`, `category_id` and `category_name` are filters; `category_name` is resolved with a
case-insensitive match and **ignored when `category_id` is also set**.

---

## Mentions: written in the text, nowhere else

`add_forum_comment` derives mentions from `@[Display Name](user-uuid)` inside `content`. **There is no
`mentions` parameter** — what's in the text is what gets notified, so the comment a human reads and the
notifications that went out can never disagree.

Every matched UUID is checked against `profiles` for existence **and** `is_active: true`. Any that don't
resolve fail the whole call, named:

```
Mencionaste usuario(s) que no existen o están inactivos: 1111…, 2222…. Verifica los UUID.
```

So resolve names with `list_team` (or `whoami` for yourself) and paste real UUIDs. A guessed UUID is
rejected, not silently dropped — which is the good outcome, but it costs you a round trip.

**Mentions work in comments, not in post bodies.** `create_forum_post`/`update_forum_post` never call
`parseMentions`. Worse, `@[Ana](uuid)` inside `content_markdown` is valid Markdown: remark reads it as a
literal `@` followed by a link whose `href` is the bare UUID, so it renders as a dead link in the post.
If you need to notify someone about a post, publish it (subscribers get `forum_post_published`) or leave
a comment that mentions them.

`parent_id` turns a comment into a reply and **must belong to the same post** — otherwise
`El comentario padre no existe o no pertenece a esta publicación.` You may comment on a published post or
on **your own** draft; anything else is `No puedes comentar en una publicación que no es pública ni es tuya.`

---

## Why there are no reaction or view tools

Deliberately absent, both of them.

**Reactions.** `popularity_score` (`calculatePopularityScore`, `packages/shared/src/forum.ts`) is
`views × 1 + reactions × 3 + comments × 5 + avg_read_seconds × 0.1`, plus a recency bonus of up to 100
decaying 2 points per day. It feeds the human-facing **"Populares"** tab (`list_forum_posts(tab: "popular")`
orders by it). A reaction is a person saying "this was useful"; an agent emitting them at machine speed
would weight a ranking humans read as a human signal. So there is no `add_forum_reaction`.

`get_forum_post` still *reports* reactions — grouped `{ emoji, count, reacted_by_me }` plus a
`reaction_count` — so you can read the signal. Read-only, by design.

For completeness: `add_forum_comment` and `delete_forum_comment` **do** call `recalculatePostPopularity`,
so commenting moves the score (×5, the heaviest term). That's accepted — a comment is substantive content
a human can read and judge, whereas a reaction is a bare vote. It does mean you should comment because
there's something to say, not to bump a post.

**Views.** `get_forum_post` never writes `forum_views` and never increments `view_count` — it's an agent
reading, not a human reading. Nothing to call, and nothing to avoid calling.

---

## Scopes

| Tools | Scope |
|---|---|
| `list_forum_posts`, `get_forum_post`, `list_forum_categories` | `forum:read` |
| `create_forum_post`, `update_forum_post`, `delete_forum_post`, `add_forum_comment`, `delete_forum_comment` | `forum:write` |

`forum:read` and `forum:write` shipped after most API keys were created, and **scopes are not granted
retroactively**. An existing key hits:

```
Permiso insuficiente: se requiere 'forum:write'
```

That is a key configuration problem, not a tool problem — nothing in the call can fix it. Tell the user to
add the scopes in **HOT → Ajustes → API keys** (edit the key's permissions; no need to rotate it), then
retry. `whoami` returns `api_key_scopes`, so you can check before you write instead of after:

```
whoami() → { …, "api_key_scopes": ["requests:read", "requests:write"] }   // no forum:* → stop and ask
```
