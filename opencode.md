# OpenGym project context

OpenGym is an offline-first Flutter gym tracker for workout plans, active set
logging, history, records, statistics, and optional account-based sync.

The app uses Provider with `ChangeNotifier` for state, Hive for local storage,
and Supabase for authentication and cross-device synchronization. Production
code is organized under `lib/` into models, providers, services, screens,
widgets, theme, data, and utilities.

Use [AGENTS.md](AGENTS.md) for development workflow, commands, code conventions,
and release requirements. Use [DESIGN.md](DESIGN.md) for the current product,
architecture, data lifecycle, and visual direction. Manual online-support checks
that cannot be automated are recorded in
[docs/online_support_verification.md](docs/online_support_verification.md).

Git history is the record of completed implementation work; this document is
kept intentionally current rather than serving as a changelog.
