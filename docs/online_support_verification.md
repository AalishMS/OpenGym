# Online support verification

The production app uses mandatory Supabase authentication and keeps Hive as its
local runtime store. The sync architecture and security invariants are described
in [DESIGN.md](../DESIGN.md).

Two deployment checks remain manual:

- In Supabase Auth URL Configuration, set the site URL to
  `https://open-gym.netlify.app` and allow redirects for
  `https://open-gym.netlify.app/**` and `http://localhost:8080/**`.
- With a real account, verify sign-up/sign-in on the deployed site, cross-device
  sync with mobile, and an offline reload after the site has been cached.

The values embedded in `SupabaseService` are publishable client configuration,
not service-role credentials. Row-level security is the security boundary.
