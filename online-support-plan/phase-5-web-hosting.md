# Phase 5 — Web hosting

**Goal:** build OpenGym for the web and host it (Netlify or Cloudflare Pages), passing Supabase
config at build time, and fix the leftover Flutter placeholders. The web build is offline-first too
(Hive uses IndexedDB in the browser).

**Depends on:** Phases 0–4. The app must build and run on a device first.

---

## Step 5.1 — Fix the web placeholders

New Flutter projects ship placeholder metadata. Update them to OpenGym.

**`web/manifest.json`** — set the app name/description/colors. Open it and REPLACE the placeholder
fields (values will look like the defaults below):

```json
  "name": "gymapp",
  "short_name": "gymapp",
  "description": "A new Flutter project.",
```

with:

```json
  "name": "OpenGym",
  "short_name": "OpenGym",
  "description": "Offline-first workout tracker with cloud sync.",
```

Also set `background_color` / `theme_color` to your dark palette (e.g. `"#0A0A0A"`) if they're still
the Flutter defaults (`#0175C2` / `#0175C2`).

**`web/index.html`** — REPLACE:

```html
  <meta name="description" content="A new Flutter project.">
```

with:

```html
  <meta name="description" content="Offline-first workout tracker with cloud sync.">
```

and REPLACE the `<title>` (likely `<title>gymapp</title>`) with:

```html
  <title>OpenGym</title>
```

Also update `apple-mobile-web-app-title` if present from `gymapp` to `OpenGym`.

> Icons: `web/icons/` ships generic Flutter icons. Optional — replace them with OpenGym icons for a
> polished install/PWA experience. Not required for functionality.

---

## Step 5.2 — Build for web

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=YOUR_URL \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Output lands in `build/web`. The anon key is compiled into the JS bundle — **this is expected and
safe** (RLS protects the data). **Never** build with the `service_role` key.

> **Renderer note:** Flutter's web renderer selection has changed across versions (HTML vs CanvasKit
> vs the newer default). Use your Flutter version's default; if fonts/canvas look off, consult
> `flutter build web --help` for the renderer flag your version exposes. Not a blocker for hosting.

Local smoke test of the production build:

```bash
dart pub global activate dhttpd
dhttpd --path build/web --port 8080
```

Open <http://localhost:8080>, sign in, confirm sync works. (A plain static server is fine locally;
the SPA redirect below matters only on the host, for deep links / refresh on a route.)

---

## Step 5.3 — Host it

Pick **one**. Both are free, HTTPS by default, support custom domains, and serve at the site root.
**Avoid GitHub Pages** for this app — its subpath hosting forces `--base-href` and routing fiddling.

### Option A — Netlify (drag-and-drop, simplest)

1. Build (Step 5.2).
2. Go to <https://app.netlify.com> → **Add new site → Deploy manually** → drag the **`build/web`**
   folder in.
3. Add the SPA redirect so a refresh on any path serves the app. Create a file
   **`build/web/_redirects`** (no extension) containing exactly:

   ```
   /*    /index.html   200
   ```

   Then re-drag `build/web`, or add this to your build script so it's always present. (Alternatively
   put a `netlify.toml` at the deploy root with the same redirect rule.)

> To automate: connect the Git repo, set build command
> `flutter build web --release --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY`
> and publish directory `build/web`, and store the two values as Netlify environment variables (site
> settings → Environment). Never commit them.

### Option B — Cloudflare Pages

1. <https://dash.cloudflare.com> → **Workers & Pages → Create → Pages**.
2. **Direct upload:** upload the `build/web` folder; or **connect the Git repo** with build command
   `flutter build web --release --dart-define=...` (you'll need the Flutter build image / a build
   step that installs Flutter) and output dir `build/web`.
3. SPA fallback: Cloudflare Pages serves `index.html` for unknown routes when you include a
   **`build/web/_redirects`** file with:

   ```
   /*    /index.html   200
   ```

4. Store `SUPABASE_URL` / `SUPABASE_ANON_KEY` as Pages environment variables if building on
   Cloudflare; never commit them.

---

## Step 5.4 — Supabase Auth URL configuration

Only strictly required if you enabled **email confirmation** or magic links (Phase 1 recommended
turning confirmation OFF for a friends project). Still good practice to set:

1. Supabase → **Authentication → URL Configuration**.
2. **Site URL:** your deployed origin, e.g. `https://opengym.netlify.app` (or your custom domain).
3. **Redirect URLs:** add your deployed origin(s) **and** `http://localhost:*` for local dev, e.g.:
   - `https://opengym.netlify.app/**`
   - `http://localhost:8080/**`

> No CORS configuration is needed for data access — the Supabase client uses your project's API
> which already allows browser origins with the anon key + RLS.

---

## Step 5.5 — Keys hygiene (final check)

- [ ] The repo contains **no** `SUPABASE_URL` / `SUPABASE_ANON_KEY` literals and **no**
      `service_role` key. They are passed via `--dart-define` (local) or host env vars (CI).
- [ ] If you use a local define file (e.g. `--dart-define-from-file`), it is in `.gitignore`.
- [ ] `build/` is git-ignored (Flutter's default `.gitignore` already ignores it).

---

## Verification checklist

- [ ] `flutter build web` succeeds with the dart-defines; `build/web` is produced.
- [ ] Local `dhttpd` serve: app loads, sign in works, a change syncs to Supabase.
- [ ] Deployed URL loads over HTTPS; **hard refresh on a non-root route** still loads the app (SPA
      redirect works).
- [ ] Sign up / sign in on the deployed site works.
- [ ] Data **syncs between the web build and the mobile build** on the same account (create on
      mobile → appears on web after foreground/refresh, and vice-versa).
- [ ] **Offline reload:** load the site, go offline (DevTools → Network → Offline), reload → cached
      data still shows (Hive/IndexedDB), writes queue and drain when back online.
- [ ] Browser tab shows **OpenGym** (title/placeholder fix), not "gymapp".

## Suggested commit

```
feat(phase-5): web build config, fix web placeholders, hosting docs
```

---

## You're done

All five phases landed: stable ids + sync metadata (0), auth (1), cloud schema + RLS (2), LWW sync
(3), first-login adoption (4), and web hosting (5). The app is still fully usable offline on every
platform; when online and signed in, plans and sessions converge across devices, each account
isolated by RLS.

**End-to-end acceptance (from the master plan):**

1. `flutter analyze` clean and `flutter test` green (after Phase 0 and again at the end).
2. Two accounts on two clients (device + `flutter run -d chrome`): create/edit/delete plans and
   sessions on each; confirm convergence and per-user isolation.
3. Offline scenario: airplane-mode edits → reconnect → drain; no duplicate sessions.
4. Migration: existing offline install → first login → data adopted once; second login, no dupes.
5. Deployed web build signs in and syncs with mobile; offline reload shows cached data.
