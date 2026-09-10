# Example: Blocked With Reason

Blocking a request and changing an already-set due date — both require a `note` param (≥5 chars) or the
DB rejects the entire call. Full mechanics: [backlog-and-readiness.md](../references/backlog-and-readiness.md).

---

## Scenario

A developer is mid-`in_progress` on "Integrar pasarela de pago" when the client stops responding with
required API credentials. The request also has a `due_date` set from creation that now needs to move.

---

## Step 1: Block, with a real reason

```
update_request_status(
  id: "req-uuid",
  status: "blocked",
  note: "esperando credenciales de la pasarela de pago del cliente, pedidas el 08/09"
)
→ { success: true, previous_status: "in_progress", new_status: "blocked", ... }
```

`note` is not optional context here — omitting it, or passing fewer than 5 characters, rejects the call
outright:

```
update_request_status(id: "req-uuid", status: "blocked")
→ Error: "Bloquear una solicitud requiere una nota de justificación de al menos 5 caracteres (parámetro note)."
```

A vague note technically passes but defeats the point:

```
update_request_status(id: "req-uuid", status: "blocked", note: "bloqueada")
→ succeeds (10 chars) but tells the next reader nothing actionable
```

Write what's blocking it **and** who/what unblocks it, not just that it's blocked.

---

## Step 2: Tell the user, and add context in the comment thread

```
add_comment(
  request_id: "req-uuid",
  content: "Bloqueada: esperando credenciales de la pasarela de pago. @[Ana Torres](ana-uuid) pidió acceso al cliente el 08/09, sin respuesta aún."
)
```

The `note` on `update_request_status` lands on the audit log (`request_status_log.note`), visible via
`get_request_history` — it is a shorter, structured justification. `add_comment` is the place for the
fuller narrative, links, and follow-up coordination. Use both; they serve different readers.

---

## Step 3: The deadline also needs to move

The `due_date` was already set at creation (`2026-09-12`). Moving it now — with the block still
active — also needs a note, since it's a change to an *already-set* value:

```
update_request(id: "req-uuid", due_date: null)
→ Error: "No se puede modificar la fecha límite sin una nota de justificación de al menos 5 caracteres (parámetro note)."

update_request(
  id: "req-uuid",
  due_date: "2026-09-22",
  note: "movida 10 días por el bloqueo de credenciales de pago, ver historial de estado"
)
→ { success: true, changes: ["fecha límite → 2026-09-22"], ... }
```

Clearing it entirely instead of moving it also requires the same note — the gate is about the fact that
an already-set `due_date` is changing at all, not about which direction:

```
update_request(id: "req-uuid", due_date: null, note: "cliente sin fecha de respuesta, se retoma cuando desbloquee")
```

---

## Step 4: Credentials arrive — unblock and resume

```
add_comment(
  request_id: "req-uuid",
  content: "Desbloqueada: cliente envió credenciales de la pasarela. Retomando integración."
)

update_request_status(id: "req-uuid", status: "in_progress")
// note is NOT required here — HT001 only gates transitions INTO "blocked"
```

---

## Step 5: Review the full trail later

```
get_request_history(request_id: "req-uuid")
→ {
    history: [
      { kind: "due_date", old_due_date: "2026-09-12", new_due_date: "2026-09-22",
        note: "movida 10 días por el bloqueo de credenciales de pago, ver historial de estado", ... },
      { kind: "status", old_status: "in_progress", new_status: "blocked",
        note: "esperando credenciales de la pasarela de pago del cliente, pedidas el 08/09", ... },
      { kind: "status", old_status: "blocked", new_status: "in_progress", note: null, ... }
    ],
    time_in_status: [
      { status: "in_progress", duration_days: 4, current: false },
      { status: "blocked",     duration_days: 6, current: false },
      { status: "in_progress", duration_days: 1, current: true }
    ]
  }
```

Both notes are right there next to the transitions they justify — this is what makes "why is this stuck"
answerable without digging through the comment thread.

---

## What NOT to do

```
// Wrong: retrying with a longer message stuffed into `content` instead of `note`
update_request_status(id: "req-uuid", status: "blocked")
add_comment(request_id: "req-uuid", content: "blocked because of missing credentials, super long explanation here...")
```

The block itself still fails with `ERRCODE HT001` — a comment can't substitute for the `note` param the
trigger actually checks. `add_comment` runs against the `updates` table; the trigger reads
`app.change_note`, which only `note` on `update_request_status`/`update_request` sets.
