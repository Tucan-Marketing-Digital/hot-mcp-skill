# Example: Authoring and Publishing a Forum Post

The canonical forum flow, end to end: identify yourself → see the real categories → create a **draft** →
verify how the Markdown actually converted → extend it → publish → comment with a mention.

Full mechanics: [forum-authoring.md](../references/forum-authoring.md).
Tool parameters: [tool-catalog.md → Forum Tools](../references/tool-catalog.md#forum-tools).

---

## Scenario

The user says: *"Escribí un post en el foro con el runbook de despliegue a staging, y avisale a Ana
cuando esté."*

So: one post, in a real category, reviewed before it goes live, plus a comment mentioning Ana.

---

## Step 0: Who am I, and can I even write to the forum?

```
whoami()
→ {
    id: "my-uuid",
    name: "Carlos Rivas",
    email: "carlos.rivas@ejemplo.com",
    role: "developer",
    api_key_scopes: ["requests:read", "requests:write", "forum:read", "forum:write", "team:read"]
  }
```

Two things checked in one call:

- **`forum:write` is in `api_key_scopes`.** If it weren't, the first write would fail with
  `Permiso insuficiente: se requiere 'forum:write'` — and nothing in the call could fix it. These scopes
  shipped after most keys were created and are **not granted retroactively**, so a key made last month
  doesn't have them. The fix is the user editing the key's permissions in **HOT → Ajustes → API keys**;
  stop and say so rather than retrying.
- **`role` is `developer`.** `create_forum_post` is admin/developer only (`forum_posts_insert_admin_developer`).
  A `designer` or `commercial` key gets
  `No tienes permiso para publicar en el foro. Solo administradores y desarrolladores pueden crear publicaciones.`

---

## Step 1: Find out which categories actually exist

```
list_forum_categories()
→ {
    total: 4,
    categories: [
      { id: "cat-anuncios",   name: "Anuncios",   color: "#f97316", icon: "megaphone", post_count: 12 },
      { id: "cat-debate",     name: "Debate",     color: "#6366f1", icon: null,        post_count: 0  },
      { id: "cat-preguntas",  name: "Preguntas",  color: "#eab308", icon: "help",      post_count: 5  },
      { id: "cat-tutoriales", name: "Tutoriales", color: "#22c55e", icon: "book",      post_count: 3  }
    ]
  }
```

A runbook is a tutorial, so `"Tutoriales"` — and `post_count: 3` confirms it's a category people
actually use, not a dormant one. **There is no `create_forum_category`**: the taxonomy is human-curated
in the app. If "Runbooks" had felt like the right home, the answer is "esa categoría no existe, lo pongo
en Tutoriales" — not inventing it.

---

## Step 2: Create the draft

```
create_forum_post(
  title: "Runbook: despliegue a staging",
  content_markdown:
    "## Requisitos\n\n" +
    "- Node 22 y pnpm 10\n" +
    "- Acceso al proyecto de Supabase de staging\n" +
    "- Variables de entorno sincronizadas\n\n" +
    "## Pasos\n\n" +
    "1. `pnpm install --frozen-lockfile`\n" +
    "2. `npx supabase migration up --linked`\n" +
    "3. `pnpm build` y revisar que no haya warnings nuevos\n" +
    "4. Desplegar y verificar `/api/health`\n\n" +
    "> Si el paso 2 falla, **no** sigas: revisá el orden de las migraciones primero.\n\n" +
    "Detalle completo en [la doc interna](https://docs.ejemplo.com/staging).",
  category_names: ["Tutoriales"],
  excerpt: "Requisitos, pasos y qué hacer si una migración falla."
)
→ {
    success: true,
    id: "post-uuid",
    slug: "runbook-despliegue-a-staging-7k2f",
    status: "draft",
    url: "/foro/runbook-despliegue-a-staging-7k2f",
    reading_time_minutes: 2,
    excerpt: "Requisitos, pasos y qué hacer si una migración falla.",
    categories: [{ id: "cat-tutoriales", name: "Tutoriales", color: "#22c55e", icon: "book" }],
    conversion: { blocks_created: 13, warnings: [] },
    notifications_dispatched: false,
    message: "Borrador creado correctamente."
  }
```

Three things to notice:

- **`status: "draft"` — that's the default, and it's the point.** The text just went through a converter
  that can silently drop constructs. Nobody has looked at the result yet. There is no `status: "published"`
  shortcut worth taking here.
- **`conversion.warnings` is empty**, so every construct landed. Had it contained
  `unsupported_markdown_node ("linkReference")`, the *visible text* of a reference-style link would have
  vanished — which is why the link above is written inline, `[la doc interna](https://…)`, not `[la doc interna][d]`.
- **The slug is `runbook-despliegue-a-staging-7k2f`** — slugified title + a random 4-char suffix. It was
  generated here and will **never** be generated again. Note it down; it's the handle for everything below.
- `notifications_dispatched: false` is correct and expected: a draft notifies nobody.

---

## Step 3: Read it back and verify the conversion

**Do not skip this.** It is the entire reason the draft default exists.

```
get_forum_post(slug: "runbook-despliegue-a-staging-7k2f")
→ {
    id: "post-uuid",
    slug: "runbook-despliegue-a-staging-7k2f",
    title: "Runbook: despliegue a staging",
    content_markdown:
      "## Requisitos\n\n- Node 22 y pnpm 10\n\n- Acceso al proyecto de Supabase de staging\n\n…",
    content_conversion: { lossy: false, dropped_block_types: [], warnings: [] },
    status: "draft",
    published_at: null,
    reading_time_minutes: 2,
    view_count: 0,
    author: { id: "my-uuid", name: "Carlos Rivas", role: "developer" },
    categories: [{ id: "cat-tutoriales", name: "Tutoriales", … }],
    reactions: [], reaction_count: 0,
    comments: [], comment_count: 0,
    url: "/foro/runbook-despliegue-a-staging-7k2f"
  }
```

`content_conversion.lossy: false` with no warnings → **the Markdown is a faithful view of the stored
post.** Good.

The list items came back separated by blank lines (`- Node 22 y pnpm 10\n\n- Acceso…`) where the input
had them tight. That is **cosmetic** — top-level blocks are re-joined with a blank line on the way out.
Same blocks, same render. Do **not** "fix" it by re-sending the whole body.

Also note `view_count: 0` after reading it: `get_forum_post` never registers a view.

> **If `lossy` had been `true`** — say the post already existed and a human had added a highlighted
> paragraph and an embedded video in the web editor — the Markdown above would be a *degraded* copy, and
> everything in Step 4 would have to use `append_markdown`. Sending `content_markdown` would write the
> degradation back over the real content, permanently.

---

## Step 4: Extend it with `append_markdown`

The user wants a rollback section added.

```
update_forum_post(
  slug: "runbook-despliegue-a-staging-7k2f",
  append_markdown:
    "## Rollback\n\n" +
    "1. Revertir el deploy desde el panel\n" +
    "2. `npx supabase migration repair --status reverted <version>`\n" +
    "3. Avisar en el canal de staging\n"
)
→ {
    success: true,
    id: "post-uuid",
    slug: "runbook-despliegue-a-staging-7k2f",
    status: "draft",
    reading_time_minutes: 3,
    excerpt: "Requisitos Node 22 y pnpm 10 Acceso al proyecto de Supabase de staging …",
    conversion: { blocks_created: 18, warnings: [] },
    notifications_dispatched: false,
    message: "Publicación actualizada correctamente."
  }
```

`append_markdown` converts **only the new text** and concatenates its blocks after the existing ones.
`content_markdown` would have replaced the whole body — a needless risk even when `lossy` is `false`,
and a destructive one when it isn't.

`reading_time_minutes` went 2 → 3 automatically. But **look at `excerpt`**: the hand-written one from
Step 2 was overwritten with an auto-generated one (the first 300 characters of the post's plain text).
Any content change regenerates the excerpt unless the **same call** passes `excerpt` explicitly. So the
call above should really have been:

```
update_forum_post(
  slug: "runbook-despliegue-a-staging-7k2f",
  append_markdown: "## Rollback\n\n…",
  excerpt: "Requisitos, pasos y qué hacer si una migración falla."   // re-send it, or lose it
)
```

An explicit `excerpt` always wins — including an explicit `null`, which clears it.

---

## Step 5: Publish

```
update_forum_post(
  slug: "runbook-despliegue-a-staging-7k2f",
  status: "published"
)
→ {
    success: true,
    id: "post-uuid",
    slug: "runbook-despliegue-a-staging-7k2f",
    status: "published",
    url: "/foro/runbook-despliegue-a-staging-7k2f",
    notifications_dispatched: true,
    message: "Publicación actualizada correctamente."
  }
```

**There is no `publish_forum_post` tool** — `update_forum_post(status:)` is both publish and unpublish.
`published_at` is set now (and, if this post is ever unpublished and republished, it will **keep** this
date rather than resetting).

`notifications_dispatched: true` means subscribers got their `forum_post_published` notification. A
`false` here would **not** mean the publish failed — the status change is already committed, and the
notification hop is fire-and-log.

---

## Step 6: Comment, mentioning Ana

```
list_team()
→ [
    { id: "ana-uuid",    name: "Ana García",   role: "developer" },
    { id: "carlos-uuid", name: "Carlos Rivas", role: "developer" },
    …
  ]

add_forum_comment(
  post_slug: "runbook-despliegue-a-staging-7k2f",
  content: "@[Ana García](ana-uuid) subí el runbook de staging, revisá el paso 2 que es el que te trabó la última vez."
)
→ {
    success: true,
    id: "comment-uuid",
    post_id: "post-uuid",
    post_slug: "runbook-despliegue-a-staging-7k2f",
    parent_id: null,
    mentioned_user_ids: ["ana-uuid"],
    notifications_dispatched: true,
    message: "Comentario agregado correctamente."
  }
```

**`mentioned_user_ids` was derived from the text.** There is no `mentions` parameter — what a human reads
in the comment and who got notified can never disagree. Ana's UUID came from `list_team`; a guessed one
would have failed the whole call with
`Mencionaste usuario(s) que no existen o están inactivos: … . Verifica los UUID.`

Note the mention went in a **comment**, not in the post body. `create_forum_post`/`update_forum_post`
never parse mentions — `@[Ana García](ana-uuid)` inside `content_markdown` is read as a plain `@` plus a
Markdown link pointing at a bare UUID, i.e. a dead link that notifies nobody.

---

## Step 7: Report back in one line

```
Publicado "Runbook: despliegue a staging" en Tutoriales
→ /foro/runbook-despliegue-a-staging-7k2f
Comenté mencionando a Ana García. Decime si querés que ajuste algo del contenido.
```

---

## What NOT to do

### Publishing straight from `create_forum_post`

```
// Wrong — nobody ever looked at how the Markdown converted
create_forum_post(title: "…", content_markdown: "…", status: "published")
```

The draft default is a review step, not a formality. Publish-on-create means a dropped HTML block, a
reference link whose text vanished, or a split blockquote goes live and notifies everyone before anyone
notices. Create → `get_forum_post` → publish.

### Replacing the whole body to add a paragraph

```
// Wrong — and destructive if content_conversion.lossy was true
get_forum_post(slug: "…")                       // → lossy: true, dropped_block_types: ["video"]
update_forum_post(slug: "…", content_markdown: <the markdown you just read> + "\n## Extra\n…")
```

That writes the lossy round-trip back over the real content: the embedded video becomes a text link, the
colours and the underline are gone, and there is no undo. Use `append_markdown`.

### Assuming the slug follows the title

```
update_forum_post(slug: "runbook-despliegue-a-staging-7k2f", title: "Runbook: despliegue a producción")
// slug is STILL runbook-despliegue-a-staging-7k2f
get_forum_post(slug: "runbook-despliegue-a-produccion-7k2f")   // → Post no encontrado o no tienes permiso para verlo.
```

The slug is generated once, at creation. It's the public URL and it's what `notifications.entity_id`
stores, so regenerating it would 404 every notification already sent. Keep using the original slug — or
just use `id`, which is stable too.

### Inventing a category

```
// Wrong
create_forum_post(title: "…", content_markdown: "…", category_names: ["Runbooks"])
→ No existen las categorías: Runbooks. Categorías válidas: Anuncios, Debate, Preguntas, Tutoriales.
```

The error is the guardrail, not a retry prompt. Call `list_forum_categories` first and pick a real one.

### Concluding the tool is broken when a draft won't load

```
// You're an admin. Someone else's draft:
get_forum_post(id: "other-authors-draft-uuid")
→ Post no encontrado o no tienes permiso para verlo.

// …but this works:
update_forum_post(id: "other-authors-draft-uuid", status: "published")
→ success: true
```

Not a bug. The SELECT policy (`forum_posts_select_published_or_own`, migration `00039`) has **no admin
branch**; UPDATE/DELETE do. `forum.ts` replicates both literally. An admin can publish or delete a draft
they cannot read. Don't retry the read, and don't report it — if an admin needs to review a draft, the
author has to publish it.

The same asymmetry hides drafts from listing: `list_forum_posts(status: "draft")` without being
self-scoped silently coerces to `published` and sets `status_filter_coerced: true`. Check that flag
before saying "no hay borradores".

### Reacting to boost a post

There is no reaction tool, deliberately. `popularity_score` weighs reactions ×3 and drives the
human-facing "Populares" tab — a reaction is a person saying "this helped". Comment if you have something
to say (that *does* move the score, ×5), but don't comment to bump a post.
