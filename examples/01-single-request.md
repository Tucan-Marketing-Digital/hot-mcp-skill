# Example: Single Request (No Project)

A standalone request not linked to any project or milestone. Simplest workflow.

---

## Scenario

A commercial team member reports: "The contact form on the website isn't sending emails."

## Flow

### Step 1: Create the request

```
whoami()
→ { id: "my-uuid", name: "Carlos Rivas", role: "admin" }
// The user named no assignee → the API-key owner owns it.

create_request(
  title: "Contact form not sending emails",
  description: "Users report that the contact form on tucanmarketing.com submits successfully but no email arrives. Started happening after last deployment.",
  priority: "high",
  category: "bug",
  domain: "development",
  assignee_ids: ["my-uuid"],
  due_date: "2026-09-04",      // high → today + 3 business days
  estimated_hours: 4
)
→ Returns: { id: "req-uuid", code: "REQ-A1B2C3", status: "assigned" }
```

> `status` comes back as `assigned`, not `pending`, precisely because `assignee_ids` was passed. A
> `pending` here would be the tell that the request was born ownerless.

Then, in the reply to the user:

```
Creada REQ-A1B2C3 — asignada a Carlos Rivas, vence 2026-09-04
(default de prioridad alta: +3 días hábiles), estimada en 4 h.
Decime si ajusto fecha, horas o responsable.
```

### Step 2: Add acceptance criteria

```
add_checklist_item(request_id: "req-uuid", title: "Root cause identified")
add_checklist_item(request_id: "req-uuid", title: "Email sending restored")
add_checklist_item(request_id: "req-uuid", title: "Test email sent and received")
```

### Step 3: Assign and start work

```
update_request_status(id: "req-uuid", status: "in_progress")
```

### Step 4: Track progress

```
update_checklist_item(id: "item-1-uuid", is_complete: true)

add_comment(
  request_id: "req-uuid",
  content: "Root cause: SMTP credentials expired after provider rotation. Updating env vars."
)
```

### Step 5: Complete remaining checklist

```
update_checklist_item(id: "item-2-uuid", is_complete: true)
update_checklist_item(id: "item-3-uuid", is_complete: true)
```

### Step 6: Resolve

```
update_request_status(id: "req-uuid", status: "resolved")
```

---

## Notes

- No `project_id` or `milestone_id` needed for standalone requests
- No GitHub integration used (quick operational fix, no code change)
- Checklist still valuable for tracking even on simple requests
- Comments document the root cause for future reference
