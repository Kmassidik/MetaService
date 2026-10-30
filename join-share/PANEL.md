# Share a PC inside the panel

The panel gets a sidebar entry **Share a PC** (under Infrastructure, after Find machines). It is the admin page of `CONTRACT.md` section 9 inside the panel, behind the panel's own login. The browser never sees the hub's admin key: the parent proxies.

```
browser (panel session, CSRF header on writes) --> parent  /api/join-share/...  --> hub admin listener 127.0.0.1:9111 (X-Admin-Key added by the parent)
```

## Parent (Swift, `control-plane/arm64`)

New settings (env, read like the others in `Root/Config/RootConfig.swift`; both optional):
- `JOIN_SHARE_ADMIN_URL`: the hub's admin listener, for example `http://127.0.0.1:9111`. Not set means the feature is off.
- `JOIN_SHARE_ADMIN_KEY_FILE`: the path of the hub's `admin.key` (read at every call, never cached, never logged, never sent to the browser).

Routes (operator session required, writes need the CSRF header like every other write; method and path are matched against this allow-list, anything else is 404, the hub is never given a path the browser chose):

| Panel route | Hub route |
|---|---|
| `GET /api/join-share/status` | answered by the parent: `{"configured": bool, "reachable": bool}` (reachable = the hub's `GET /admin/supported` answered 200) |
| `GET /api/join-share/supported` | `GET /admin/supported` |
| `POST /api/join-share/links` | `POST /admin/links` |
| `GET /api/join-share/pending` | `GET /admin/pending` |
| `POST /api/join-share/pending/<id>/approve` | `POST /admin/pending/<id>/approve` |
| `POST /api/join-share/pending/<id>/refuse` | `POST /admin/pending/<id>/refuse` |
| `GET /api/join-share/peers` | `GET /admin/peers` |
| `DELETE /api/join-share/peers/<name>` | `DELETE /admin/peers/<name>` |

The hub's status code and JSON body are passed through unchanged (so `403 {"error":"wrong_code","tries_left":n}` reaches the page), except: not configured gives `404 {"error":"not_configured"}`, the hub unreachable gives `502 {"error":"hub_unreachable"}`. `<id>` and `<name>` are checked (letters, digits, `.`, `-`, `_`, at most 64) before they go into a path. Request bodies are limited to 16 KiB and forwarded as JSON only. A short timeout (10 s). Each write (links, approve, refuse, remove) is written to the audit log with the operator's name and the target, never the code or the key.

## Panel (Svelte, `frontend`)

Sidebar item **Share a PC** (route `#/share`), one page. It does what `join-share/web/app.js` does (read it; reuse its logic and wording): three buttons Mac / Windows / Linux, then the CPU choices with the states from `/supported` (ready, "not tested yet", "no build yet", "coming soon" disabled with a one-line reason), the generated command with a Copy button, the pending machines with a code field and Approve / Refuse (wrong code shows the tries left), the joined machines with Remove. Use the panel's own components and styles (it is the same look). States with text for: loading, the feature not set up (`not_configured`), the hub not answering (`hub_unreachable`), nothing pending, nothing joined. The page polls every 4 s while it is open, redraws a list only when it changed (a half-typed code must not be lost), and stops polling when the page is closed. Untrusted text (hostnames come from far PCs) is shown as text, never as HTML.
