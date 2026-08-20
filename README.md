# PickEm

A full-stack NFL pick'em challenge app. Users join groups, pick games against the spread each week, and compete on a season-long leaderboard.

---

## Repositories

| Directory | Description |
|-----------|-------------|
| `PickEm-iOS/` | Native iOS app — SwiftUI, clean MVVM |
| `pickem-api/` | REST API — FastAPI, PostgreSQL, deployed on Fly.io |

---

## Summary & Design Rationale

PickEm started as a general "pick'em" concept with room for multiple sports and challenge formats, and was deliberately scoped down to **NFL only, season-long standings**. That narrowing shows up in the data model — `Group.sport` and `Group.mode` still exist as plain string fields rather than enums with real branching logic, because there's currently only one value for either. They're cheap to leave in place and would be the natural extension point if the scope ever widens again, but nothing in the app today treats them as configurable.

A few of the bigger technical decisions, and the reasoning behind them:

**Authentication — short-lived JWT + revocable opaque refresh token, not one or the other.** A single long-lived JWT would be simplest, but a compromised or lost device would have no way to be logged out remotely — a JWT is only valid as long as its own expiry, with no way to revoke it early short of a server-side blocklist (which erases the whole point of a stateless token). So auth is split in two: a JWT access token that's short-lived (30 min) and requires no DB lookup on every request, and a random opaque refresh token whose *bcrypt hash* (never the raw value) is stored server-side — logout or a compromised-device response is just deleting that row. Passwords are checked with a constant-time comparison against a dummy hash even when the email doesn't exist, so a login attempt can't be used to enumerate real accounts by response timing.

**PostgreSQL, with standings materialized rather than computed on read.** The data is inherently relational — users, groups, memberships, weeks, games, and picks all have real foreign-key relationships, and grading a single game result has to atomically update every affected pick *and* every affected standings row in one transaction. That's a natural fit for a relational database with real transactions, not a document store. Standings themselves are pre-computed into their own table at result-processing time rather than aggregated from picks at read time, because the leaderboard is the highest-traffic read in the app — it should be one indexed row-scan, not a fan-out `GROUP BY` over every pick ever made. Schema changes only ever happen through Alembic migrations, checked into the repo, so "what does the schema look like" is always answerable from git history rather than tribal knowledge of manual `ALTER TABLE`s.

**Fly.io, with the machine allowed to suspend when idle.** This app has real but bursty, low-overall traffic — a handful of active pick'em groups, not a high-QPS product — so an always-on machine would mostly be paying to idle. `fly.toml` sets `auto_stop_machines = "suspend"`: the machine spins down after a period of no requests and wakes back up on the next one. The trade-off we accepted knowingly: background jobs (pick reminders, the pre-kickoff odds refresh) live in an in-memory scheduler, so a job whose fire time lands exactly during a suspend window can be silently lost. We chose to accept that risk rather than pay for an always-on machine just to guarantee job delivery — see `pickem-api/README.md`'s Background Jobs section for exactly which jobs are affected. Migrations are wired into the deploy itself (`release_command = "alembic upgrade head"` in `fly.toml`), so applying a new schema is never a manual step someone has to remember to run after deploying.

**Caching the Odds API aggressively, and locking the line before kickoff.** The Odds API's free tier caps out at 500 requests/month, so every avoidable call is real quota. Odds are fetched into a shared pool in Postgres — once per real matchup, not once per group — and reused across every group whose slate includes that game, with a scheduled refresh cadence (on startup, every 24h, and once more 30 minutes before each slate-added game's own kickoff) instead of fetching on every request. That last refresh also **locks** the game's spread permanently once it fires: after that point nothing can move the number again. That's a deliberate trade-off of "always show the freshest possible line" in favor of "grade picks fairly" — without a lock, a line that moved between when someone picked and when the game kicked off could flip a pick from a win to a loss against a number the member never actually saw. Freezing it right before kickoff means the number everyone picked against and the number it's graded on are guaranteed to be the same one. Full timing details are in `pickem-api/README.md`'s Background Jobs & Caching section.

---

## Features

### Groups

- Any user can create a group and becomes its **admin**. The admin is a full participant — they pick games and appear on the leaderboard.
- Members join via a **6-character alphanumeric join code** shared by the admin.
- A user can belong to multiple groups. Each group has fully isolated picks, results, and standings.
- Group configuration is set at creation and includes:
  - **Blind picks** — when enabled, other members' picks are hidden until that game's kickoff. Enforced server-side.
  - **Superdogs** — an optional feature the admin can enable (see below).
  - **Preseason / playoffs** — the admin chooses whether the group's standard weeks include the 4 preseason weeks and/or the playoffs. Weeks map directly onto the real NFL season structure (Preseason Week 1-4 → Week 1-18 → Wild Card/Divisional/Conference Championships/Super Bowl) and are created empty as soon as the group exists — the admin then picks which games from the odds pool go into each week's slate; nothing is auto-selected. All group members are notified as soon as the admin adds the first game to a week.

### Picks & Scoring

- Users pick the favorite or underdog against the spread for each game.
- Picks lock at kickoff of each individual game — later games in a slate remain open even after earlier ones start.
- **Spread rounding**: all spreads are rounded to the nearest 0.5 away from zero (e.g. -3.0 → -3.5) so a push is impossible. Only the rounded value is stored.
- **WIN = +1, LOSS = +0**, no pushes by design.

### Superdogs

An optional pick modifier the admin enables at group creation. When a game's spread (after rounding) is ≥ 6.5, a user may declare a "superdog" on the underdog — betting the underdog wins outright.

- Underdog wins outright → **+3 wins**
- Underdog loses → **-1 (loss)**

The admin sets the total number of superdogs each user is allowed for the season. All three eligibility conditions (group setting, spread threshold, user limit) are validated server-side.

### Leaderboard / Standings

- Sorted by win percentage descending, with total effective wins as a tiebreaker.
- Superdog wins count as 3 for win-percentage and tiebreaker calculations.
- Standings are pre-computed in a materialized `standings` table updated whenever results are processed — leaderboard reads are a single indexed query.

### Notifications

- **Admin**: reminder to finalize the pick slate 3 hours before the first game kickoff.
- **All members**: pick reminders at T-120, T-60, T-30, and T-15 minutes before each game they haven't picked yet.
- **All members**: result notification when scores are posted for a slate.
- A silent FCM data push triggers iOS cache invalidation when the admin finalizes a slate or results are posted.

---

## Architecture

### iOS (`PickEm-iOS/`)

**Language/UI**: Swift + SwiftUI, async/await throughout.

**Pattern**: Clean MVVM with strict layer separation.

| Layer | Responsibility |
|-------|---------------|
| `Domain/` | App-facing models (`Game`, `Pick`, `Standing`, …) with enums, business logic, and computed properties |
| `DTOs/` | API response shapes with `toDomain()` mappers |
| `Repositories/` | Protocol-based data access; three implementations (Live, MockBackend, MockLocal) |
| `Services/` | `NetworkService` (auth header injection, token refresh), `LocalCacheService` (SwiftData), `NotificationService` (APNs/FCM) |
| `ViewModels/` | `@MainActor ObservableObject`s that hold UI state and call repositories |
| `Views/` | Pure SwiftUI — no business logic |

**Repository implementations** — switching requires changing one constant in `AppDependencies.swift`:

| Implementation | Used for |
|---------------|---------|
| `LiveRepository` | Production — calls the Fly.io backend over HTTPS |
| `MockBackendRepository` | Phase 2 dev — calls the local FastAPI server |
| `LocalMockRepository` | Unit tests and SwiftUI Previews — no network calls |

**Local caching**: SwiftData caches the current week's games, the current user's own picks, and standings. Cache is invalidated on foreground, pull-to-refresh, or silent FCM data push.

**Push notifications**: APNs via Firebase Cloud Messaging (FCM only — no other Firebase services).

### Backend (`pickem-api/`)

**Language/framework**: Python 3.12+, FastAPI, SQLModel (SQLAlchemy + Pydantic), Alembic migrations.

**Auth**: JWT access tokens (short-lived) + refresh tokens (long-lived, hashed and stored in DB). bcrypt password hashing with constant-time comparison to prevent timing attacks.

**Odds data**: Fetched from [The Odds API](https://the-odds-api.com) and cached in Postgres. The iOS app never calls the Odds API directly. A configurable staleness threshold (`ODDS_CACHE_TTL_MINUTES`) triggers a background re-fetch when an admin views available games.

**Scheduling**: APScheduler drives periodic odds fetches and pick-reminder notifications. Separate jobs are scheduled per-game when games are added to a slate; cancelled if games are removed.

**Push notifications**: FCM HTTP v1 API via a Google service account OAuth2 token.

**Deployment**: Dockerized, deployed to Fly.io with a Fly.io Postgres instance.

### Database

PostgreSQL. Key tables:

| Table | Description |
|-------|-------------|
| `users` | Accounts; stores FCM token (updated on each app launch) |
| `refresh_tokens` | Hashed long-lived tokens for JWT refresh |
| `groups` | Group configuration (blind_picks, superdogs, preseason/playoffs) |
| `group_members` | Group membership join table |
| `weeks` | Time-boxed pick slates; belong to a group |
| `games` | Games sourced from the Odds API; cached with rounded spread and `odds_api_id` for dedup. `week_id=NULL` means the game is in the odds pool, not yet on a slate |
| `picks` | One row per user/game/group triple; stores `picked_team`, `is_superdog`, and `result` |
| `standings` | Materialized leaderboard; written transactionally when results are processed |

---

## API Reference

All endpoints require `Authorization: Bearer <access_token>` unless noted. Interactive docs available at `/docs` in development mode.

### Auth

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/auth/register` | Create account → `{ access_token, refresh_token, user }` |
| `POST` | `/auth/login` | Email + password → `{ access_token, refresh_token, user }` |
| `POST` | `/auth/refresh` | Exchange refresh token → `{ access_token }` |
| `POST` | `/auth/logout` | Invalidate a refresh token |
| `PUT` | `/auth/fcm-token` | Store device FCM token (called on every app launch) |

### Groups

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/groups` | User | Create a group; creator becomes admin and member |
| `GET` | `/groups` | User | List groups the current user belongs to |
| `GET` | `/groups/{id}` | Member | Group detail |
| `POST` | `/groups/join` | User | Join a group by join code |
| `DELETE` | `/groups/{id}/members/{user_id}` | Admin | Remove a member |

### Weeks & Slate Management

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/groups/{id}/weeks` | Member | List all weeks/slates |
| `POST` | `/groups/{id}/weeks` | Admin | Create a new week |
| `GET` | `/groups/{id}/weeks/{week_id}/games` | Member | Games in a slate, ordered by kickoff |
| `POST` | `/groups/{id}/weeks/{week_id}/games` | Admin | Add a game from the odds pool to a slate |
| `DELETE` | `/groups/{id}/weeks/{week_id}/games/{game_id}` | Admin | Remove a game from a slate (returns it to pool) |
| `GET` | `/odds/available?sport=…` | User | Available games in the odds pool for a sport |

Slate modifications are locked once the first game of the slate has kicked off.

### Picks

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/picks` | Member | Submit a pick (locked at game kickoff) |
| `PUT` | `/picks/{id}` | Owner | Update a pick (locked at kickoff) |
| `GET` | `/groups/{id}/weeks/{week_id}/picks` | Member | Picks for a week; blind_picks visibility enforced server-side |

### Standings

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/groups/{id}/standings` | Member | Leaderboard sorted by win%, then total effective wins |

### Dev (development only — 404 in production)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/dev/mock-games` | Seed odds pool with mock games (`sport`, `week_label`, `game_count`) |
| `POST` | `/dev/mock-results` | Post a result for a game; triggers the full result pipeline |
| `POST` | `/dev/seed-week` | One-shot: create a week for a group and populate it with mock games |
| `GET` | `/dev/mock-templates` | List available team matchup templates for each sport |

### Health

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Returns `{ status, env }` — used by Fly.io and load balancers |

---

## Result Processing Pipeline

Triggered by `POST /dev/mock-results` in development, or by the Odds API results scheduler in production:

1. Record `home_score` and `away_score` on the game.
2. Determine which team covered the (rounded) spread.
3. Score each pick:
   - `is_superdog=true`: underdog wins outright → `superdog_win`; otherwise → `loss`
   - Otherwise: covered → `win`; didn't cover → `loss`
4. Update the `standings` row for each affected user in the group (transactional).
5. Mark `result_posted=true` on the game.
6. Send FCM result notification + silent cache-invalidation push to all group members.

---

## Mock Backend Test Accounts

Run `pickem-api/scripts/seed_dev.py` to wipe and reseed the development database with a consistent dataset. All accounts use password `password123`.

| Email | Name | Role |
|-------|------|------|
| `alice@test.com` | Alice | Admin |
| `bob@test.com` | Bob | Member |
| `charlie@test.com` | Charlie | Member |
| `diana@test.com` | Diana | Member |

One group is created — **Sunday Crew** (superdogs on) — simulating Week 9 of the season, with Weeks 1-8 fully played out and Week 9 containing a final, a live, and two upcoming games. See [`pickem-api/README.md`](pickem-api/README.md#seeding-mock-data-phase-2) for full details including expected standings.

---

## Build Phases

| Phase | Status | Description |
|-------|--------|-------------|
| **Phase 1** | ✅ Complete | Full iOS app against `LocalMockRepository` — all screens, ViewModels, and domain logic |
| **Phase 2** | 🔄 In progress | FastAPI backend with mock data; iOS on `MockBackendRepository` |
| **Phase 3** | Pending | Live Odds API integration; scheduler, odds cache, spread rounding against real data |
| **Phase 4** | Pending | Production deployment + FCM push notifications end-to-end |

---

## See Also

- [`pickem-api/README.md`](pickem-api/README.md) — API setup, local dev, migrations, deployment
- [`PickEm-iOS/README.md`](PickEm-iOS/README.md) — iOS scheme configuration, running tests, APNs setup
