# PickEm App — Master Build Prompt

## Overview

Build a full-stack sports pick'em challenge app. Users join groups, pick games against the spread, and compete on a season-long leaderboard. The app supports two challenge modes — a structured NFL season mode and a structured FIFA World Cup tournament mode.

---

## Business Requirements

### Challenge Modes

- **Season Mode** — Tied to a full sport season (NFL). Weekly picks run for the entire season including playoffs and championship games. Records accumulate across the full season.
- **World Cup Mode** — Tied to the FIFA World Cup tournament. Every game is included: all group stage matchdays, Round of 32, Round of 16, Quarter-Finals, Semi-Finals, and the Final. Records accumulate across the full tournament. The 2026 World Cup (48 teams) is the initial supported year.

### Groups

- Any authenticated user can create a group and becomes its **admin**.
- The admin is automatically added as a full participating member of the group on creation — they submit picks, appear on the leaderboard, and receive all the same member notifications as any other participant.
- The admin shares a **join code** that other users can enter to join the group.
- One user can belong to multiple groups.
- Each group has its own isolated leaderboard, picks, and challenge configuration.

### Game Selection (Admin)

- The admin selects which games are included in each week's pick slate from available games returned by the odds system.
- For NFL, this typically includes every primetime game plus a curated set of Sunday afternoon games and all playoff/Super Bowl games.
- For World Cup, all games in a round are automatically included in the slate once odds become available — the admin does not need to curate them manually. The admin can still remove individual games if needed.
- The admin can add or remove games from the slate up until the first game of that slate kicks off.

### Spreads & Scoring Rules

- All spreads must be rounded to the nearest 0.5 such that a push is impossible. If the Odds API returns -3.0, it is stored and displayed as -3.5 (always round away from zero by 0.5). The raw value from the Odds API is discarded after rounding — only the rounded spread is stored.
- A user picks either the favorite or the underdog against the spread for each game.
- Standard result: WIN = +1, LOSS = +0, no pushes by design.
- **Superdog**: An optional feature configured by the admin when creating a group challenge. The admin sets `superdogs_enabled` (bool) and `superdogs_per_user` (int, e.g. 3) at challenge creation time. When enabled: for any game where the spread is >= 6.5 (after rounding), a user may declare a "superdog" on the underdog — meaning they are picking the underdog to win outright, not just cover. If the underdog wins outright, the pick counts as **3 wins**. If the underdog loses, it counts as **1 loss**. Superdogs can be enabled on any challenge mode (Season or Custom).

### Picks Behavior

- Picks lock at kickoff of each individual game (not the whole slate at once). A user can still pick later games in a slate even after an earlier game has kicked off.
- Users can edit their pick for a game up until that game's kickoff time.
- **Pick visibility** is configured by the admin at challenge creation via a `blind_picks` flag (bool):
  - `blind_picks = true` — users cannot see each other's picks until after that game's kickoff. Other users' picks are omitted entirely from the API response for any game that has not yet kicked off (enforced server-side, not just client-side).
  - `blind_picks = false` — users can see each other's picks as they are submitted, regardless of kickoff time.
- A user can always see their own picks regardless of this setting.

### Notifications

- The **admin** receives a push notification reminding them to finalize the pick slate **3 hours before the first game kickoff** of each week/slate period. This notification is sent regardless of whether a slate has already been curated, as a confirmation prompt.
- **All members** (including the admin) receive pick reminders for each game they have not yet picked:
  - **2 hours** before that game kicks off
  - **1 hour** before kickoff (if no pick submitted)
  - **30 minutes** before kickoff (if no pick submitted)
  - **15 minutes** before kickoff (if no pick submitted)
- All members receive a notification when results are posted for a slate.

### Leaderboard

- Displays all group members' season/challenge records (W-L, win %, superdogs remaining if enabled).
- Visible to all group members at all times.
- Sorted by win percentage, then total wins as tiebreaker.

---

## Tech Stack

### iOS
- **Language**: Swift (latest stable)
- **UI**: SwiftUI
- **Concurrency**: async/await throughout — no Combine or callback-based patterns
- **Architecture**: Clean MVVM
  - `Repository` layer — abstracts all data access; can be swapped between live, cached, and mock implementations
  - `Service` layer — raw network/database calls, consumed by repositories
  - `DTO` layer — maps directly to API response shapes
  - `Domain Model` layer — app-facing models with enums, computed properties, business logic helpers
  - `ViewModel` layer — drives SwiftUI views, holds UI state, calls repositories
  - `View` layer — pure SwiftUI, no business logic
- **Local persistence**: SwiftData (or Core Data if SwiftData proves limiting) for offline caching of picks and leaderboard
- **Push notifications**: APNs via FCM (Firebase Cloud Messaging) — FCM only, no other Firebase services
- **Testing**: XCTest with high unit test coverage on ViewModels, Repositories, and Domain Models

### Backend
- **Language**: Python 3.12+
- **Framework**: FastAPI
- **ORM**: SQLModel (shared Pydantic + SQLAlchemy models)
- **Migrations**: Alembic
- **Auth**: JWT (python-jose + passlib[bcrypt]). Email/password registration + login. JWT access tokens (short-lived) + refresh tokens (long-lived, stored in DB).
- **Scheduler**: APScheduler for odds fetching jobs
- **HTTP client**: httpx (async) for Odds API calls
- **Push notifications**: httpx call to FCM HTTP v1 API
- **Docs**: Auto-generated via FastAPI's OpenAPI integration; all endpoints, schemas, and error codes documented

### Database & Deployment
- **Database**: PostgreSQL on Fly.io
- **App hosting**: Fly.io (Dockerized FastAPI app)
- **Config**: pydantic-settings for environment variable management

### Odds Data
- **Provider**: [The Odds API](https://the-odds-api.com)
- **Endpoint used**: `/v4/sports/{sport}/odds` with `markets=spreads`
- **Fetch strategy**: Backend fetches and caches odds in Postgres. iOS never calls The Odds API directly.

---

## Caching Strategy

### Layer 1: Odds API → Postgres (Backend Cache)

The Odds API charges per request. The app always reads from Postgres — never directly from the Odds API.

**Scheduled refresh cadence:**
- Once or twice daily during the week to capture line movement
- One final fetch ~3 hours before the first kickoff of each slate (aligned with the admin slate-curation notification)
- In `development` mode, the scheduler is disabled entirely — all game data comes from `/dev/mock-games`

**Staleness awareness:**
- Each game row stores an `odds_fetched_at` timestamp
- When an admin hits `GET /odds/available` to build a slate, if data is older than a configurable threshold (`ODDS_CACHE_TTL_MINUTES`, default 120), a background re-fetch is triggered via a FastAPI `BackgroundTask` — the stale data is returned immediately and refreshed asynchronously

### Layer 2: iOS On-Device Cache (SwiftData)

**What to cache:**
- Current week's games + spreads — written to SwiftData on first fetch, used for offline reads and instant load on app re-launch
- The current user's own picks — always available offline; treated as source of truth until a sync confirms otherwise
- Standings / leaderboard — acceptable to be slightly stale between explicit refreshes

**What not to cache (always fetch fresh):**
- Other users' picks in a blind challenge — a stale "no pick" when they actually picked would be misleading
- Game results — always re-fetch when a result notification arrives

**Invalidation strategy:**
- **Foreground refresh** — on every app foreground event, re-fetch current week games and standings in the background and update the SwiftData store
- **Pull-to-refresh** — all list views support explicit pull-to-refresh
- **FCM silent push** — the backend sends a silent (non-alerting) FCM data message for two high-value events: (1) admin finalizes the slate, (2) results are posted. On receipt, iOS discards the SwiftData cache for that scope and re-fetches immediately. This is the primary mechanism for keeping the app current without polling.

### Layer 3: Standings (Postgres Materialized Table)

- Standings are not computed on read. A `standings` table is updated transactionally every time results are processed.
- This keeps leaderboard reads to a simple single-table query with no joins.
- The table is the write-through cache — no separate Redis or application-level cache needed for v1.

---

## Development / Mock Data Strategy

### Backend Dev Mode

- Controlled via an environment variable: `APP_ENV=development | production`
- In `development` mode:
  - A `/dev/mock-games` endpoint allows seeding the database with realistic mock game data (teams, spreads, kickoff times) for either supported sport (NFL or World Cup), without hitting The Odds API
  - A `/dev/mock-results` endpoint allows simulating game results for any seeded mock game, triggering the same result processing pipeline as real games
  - The odds fetch scheduler is disabled; all game data comes from mock seeds
  - These `/dev/` endpoints are completely unavailable in `production` mode (return 404)
- Mock data should be structurally identical to real Odds API responses so no other code paths differ

### iOS Data Layer

The iOS `Repository` protocol must support three interchangeable implementations:

1. **LiveRepository** — calls the real FastAPI backend over HTTPS
2. **MockBackendRepository** — calls the FastAPI backend running locally in dev mode (uses dev mock endpoints)
3. **LocalMockRepository** — returns hardcoded in-memory mock data; used for unit tests and SwiftUI previews; no network calls whatsoever

Switching between implementations should require changing a single constant or scheme environment variable. ViewModels and Views must be entirely unaware of which implementation is active.

---

## Project Structure

### iOS — `PickEm-iOS/`

```
PickEm/
├── App/
│   ├── PickEmApp.swift
│   └── AppDependencies.swift        # Dependency injection root — swap repo implementations here
├── Domain/
│   ├── Models/
│   │   ├── User.swift
│   │   ├── Group.swift
│   │   ├── Game.swift               # Includes spread rounding logic, superdog eligibility computed property
│   │   ├── Pick.swift               # Includes PickResult enum: win, loss, superdog
│   │   ├── Week.swift
│   │   └── Standing.swift
│   └── Enums/
│       ├── Sport.swift              # nfl, worldCup
│       ├── ChallengeMode.swift      # season, worldCup
│       └── PickResult.swift
├── DTOs/
│   ├── UserDTO.swift
│   ├── GameDTO.swift
│   ├── PickDTO.swift
│   └── StandingDTO.swift
├── Repositories/
│   ├── Protocols/
│   │   ├── GameRepositoryProtocol.swift
│   │   ├── PickRepositoryProtocol.swift
│   │   ├── AuthRepositoryProtocol.swift
│   │   ├── GroupRepositoryProtocol.swift
│   │   └── StandingsRepositoryProtocol.swift
│   ├── Live/
│   │   ├── LiveGameRepository.swift
│   │   ├── LivePickRepository.swift
│   │   ├── LiveAuthRepository.swift
│   │   ├── LiveGroupRepository.swift
│   │   └── LiveStandingsRepository.swift
│   └── Mock/
│       ├── MockGameRepository.swift
│       ├── MockPickRepository.swift
│       ├── MockAuthRepository.swift
│       ├── MockGroupRepository.swift
│       └── MockStandingsRepository.swift
├── Services/
│   ├── NetworkService.swift         # Base HTTPS client, auth header injection, token refresh
│   ├── LocalCacheService.swift      # SwiftData context wrapper; exposes invalidate(scope:) for FCM-triggered refresh
│   └── NotificationService.swift   # APNs token registration, FCM token upload, silent push handling
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── GroupViewModel.swift
│   ├── SlateViewModel.swift         # Current week's games + pick state
│   ├── PickViewModel.swift
│   └── StandingsViewModel.swift
├── Views/
│   ├── Auth/
│   │   ├── LoginView.swift
│   │   └── RegisterView.swift
│   ├── Groups/
│   │   ├── GroupListView.swift
│   │   ├── CreateGroupView.swift
│   │   └── JoinGroupView.swift
│   ├── Slate/
│   │   ├── SlateView.swift          # This week's games
│   │   ├── GameRowView.swift
│   │   └── PickSubmissionView.swift
│   ├── Standings/
│   │   └── LeaderboardView.swift
│   └── Common/
│       ├── LoadingView.swift
│       └── ErrorView.swift
└── Tests/
    ├── ViewModelTests/
    ├── RepositoryTests/
    └── DomainModelTests/
```

### Backend — `pickem-api/`

```
pickem-api/
├── app/
│   ├── main.py                      # FastAPI app init, router registration, lifespan
│   ├── database.py                  # SQLModel engine, session dependency
│   ├── config.py                    # pydantic-settings config, APP_ENV check
│   ├── auth/
│   │   ├── jwt.py                   # Token creation, validation, refresh
│   │   ├── dependencies.py          # get_current_user Depends()
│   │   └── password.py              # bcrypt helpers
│   ├── models/
│   │   ├── user.py
│   │   ├── group.py
│   │   ├── game.py                  # Includes spread rounding on write
│   │   ├── pick.py
│   │   ├── week.py
│   │   └── standing.py              # Computed or materialized view
│   ├── routers/
│   │   ├── auth.py                  # POST /auth/register, /auth/login, /auth/refresh
│   │   ├── groups.py                # CRUD + join code
│   │   ├── games.py                 # GET /groups/{id}/games, admin slate management
│   │   ├── picks.py                 # POST/PUT /picks, GET with visibility rules
│   │   ├── standings.py             # GET /groups/{id}/standings
│   │   └── dev.py                   # /dev/mock-games, /dev/mock-results (dev only)
│   ├── services/
│   │   ├── odds.py                  # Odds API client + spread rounding logic
│   │   ├── results.py               # Process game results, update pick outcomes
│   │   ├── notifications.py         # FCM push notification sender
│   │   └── scheduler.py             # APScheduler jobs: odds fetch, notif triggers
│   └── schemas/                     # Pydantic request/response schemas (separate from SQLModels)
│       ├── auth.py
│       ├── game.py
│       ├── pick.py
│       └── standing.py
├── alembic/
│   └── versions/
├── tests/
│   ├── test_auth.py
│   ├── test_picks.py
│   ├── test_results.py
│   └── test_spread_rounding.py
├── Dockerfile
├── fly.toml
├── requirements.txt
└── .env.example
```

---

## Database Schema

```sql
-- Users
users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT UNIQUE NOT NULL,
  display_name  TEXT NOT NULL,
  hashed_pw     TEXT NOT NULL,
  fcm_token     TEXT,                     -- updated on each app launch
  created_at    TIMESTAMPTZ DEFAULT now()
)

-- Refresh tokens
refresh_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES users(id) ON DELETE CASCADE,
  token_hash    TEXT NOT NULL,
  expires_at    TIMESTAMPTZ NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT now()
)

-- Groups
groups (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                TEXT NOT NULL,
  admin_id            UUID REFERENCES users(id),
  join_code           TEXT UNIQUE NOT NULL,     -- short alphanumeric, generated on create
  sport               TEXT NOT NULL,            -- 'americanfootball_nfl', 'soccer_fifa_world_cup'
  mode                TEXT NOT NULL,            -- 'season' | 'worldCup'
  season_year         INT NOT NULL,             -- e.g. 2025 for NFL, 2026 for World Cup
  blind_picks         BOOLEAN DEFAULT TRUE,     -- if true, picks hidden until kickoff
  superdogs_enabled   BOOLEAN DEFAULT FALSE,    -- if true, superdog declarations allowed
  superdogs_per_user  INT DEFAULT 3,            -- max superdog declarations per user; ignored if superdogs_enabled=false
  created_at          TIMESTAMPTZ DEFAULT now()
)

-- Group membership
group_members (
  group_id      UUID REFERENCES groups(id) ON DELETE CASCADE,
  user_id       UUID REFERENCES users(id) ON DELETE CASCADE,
  joined_at     TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
)

-- Weeks / slates
weeks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      UUID REFERENCES groups(id) ON DELETE CASCADE,
  week_number   INT NOT NULL,
  label         TEXT NOT NULL,            -- e.g. "Week 12", "Playoffs - Divisional", "Group Stage - Matchday 1", "Round of 16"
  created_at    TIMESTAMPTZ DEFAULT now()
)

-- Games (sourced from Odds API, cached in DB)
games (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  week_id       UUID REFERENCES weeks(id) ON DELETE CASCADE,
  odds_api_id   TEXT UNIQUE,             -- external ID for dedup on re-fetch
  sport         TEXT NOT NULL,
  home_team     TEXT NOT NULL,
  away_team     TEXT NOT NULL,
  spread        NUMERIC(5,1) NOT NULL,   -- rounded to nearest 0.5 on ingest (no push possible)
  favorite_team TEXT NOT NULL,           -- team the spread favors
  kickoff_at    TIMESTAMPTZ NOT NULL,
  home_score    INT,                     -- null until result posted
  away_score    INT,                     -- null until result posted
  result_posted BOOLEAN DEFAULT FALSE,
  odds_fetched_at TIMESTAMPTZ NOT NULL        -- timestamp of last odds ingest for this game
)

-- Picks
picks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  game_id         UUID REFERENCES games(id) ON DELETE CASCADE,
  group_id        UUID REFERENCES groups(id) ON DELETE CASCADE,
  picked_team     TEXT NOT NULL,
  is_superdog     BOOLEAN DEFAULT FALSE,
  result          TEXT,                  -- 'win' | 'loss' | 'superdog_win' | 'pending'
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, game_id, group_id)
)

-- Standings (materialized, updated when results are posted)
standings (
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  group_id        UUID REFERENCES groups(id) ON DELETE CASCADE,
  wins            INT DEFAULT 0,
  losses          INT DEFAULT 0,
  superdog_wins   INT DEFAULT 0,         -- count of superdog wins (each = 3 in record)
  superdogs_used  INT DEFAULT 0,         -- out of 3 allowed per season
  updated_at      TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, group_id)
)
```

---

## API Endpoints

### Auth
```
POST   /auth/register         { email, display_name, password } → { access_token, refresh_token, user }
POST   /auth/login            { email, password } → { access_token, refresh_token, user }
POST   /auth/refresh          { refresh_token } → { access_token }
POST   /auth/logout           (auth required) invalidates refresh token
PUT    /auth/fcm-token        (auth required) { fcm_token } → updates device token
```

### Groups
```
POST   /groups                (auth) { name, sport, mode, season_year, blind_picks, superdogs_enabled, superdogs_per_user? } → group + join_code
GET    /groups                (auth) → groups the current user belongs to
GET    /groups/{id}           (auth, member) → group detail
POST   /groups/join           (auth) { join_code } → joins group, returns group
DELETE /groups/{id}/members/{user_id}  (auth, admin) → remove member
```

### Games / Slate
```
GET    /groups/{id}/weeks              (auth, member) → list of weeks
GET    /groups/{id}/weeks/{week_id}/games  (auth, member) → games with spreads + pick state
POST   /groups/{id}/weeks             (auth, admin) → create a new week/slate
POST   /groups/{id}/weeks/{week_id}/games  (auth, admin) → add game to slate (by odds_api_id)
DELETE /groups/{id}/weeks/{week_id}/games/{game_id}  (auth, admin) → remove game from slate
GET    /odds/available        (auth) { sport, date_from?, date_to? } → available games from cache or Odds API
```

### Picks
```
POST   /picks                 (auth) { game_id, group_id, picked_team, is_superdog? } → pick
PUT    /picks/{id}            (auth, owner, before kickoff) { picked_team, is_superdog? } → updated pick
GET    /groups/{id}/weeks/{week_id}/picks  (auth, member) → picks (own always visible; others visible after kickoff)
```

### Standings
```
GET    /groups/{id}/standings  (auth, member) → leaderboard sorted by win%, then total wins
```

### Dev (development only — 404 in production)
```
POST   /dev/mock-games        { sport, week_label, game_count } → seeds mock games into DB
POST   /dev/mock-results      { game_id, home_score, away_score } → posts result, triggers result pipeline
GET    /dev/mock-templates    → returns available mock game templates (teams, typical spreads) for NFL and World Cup
```

---

## Key Business Logic Notes

### Spread Rounding
- Performed on ingest from the Odds API, before writing to DB. The raw value is discarded.
- Rule: if the Odds API value ends in `.0`, add `0.5` in the direction away from zero
  - `-3.0` → `-3.5`
  - `-3.5` → unchanged (already a half-point spread)
  - `-7.0` → `-7.5`
- Only the rounded `spread` is stored and used everywhere downstream

### Superdog Eligibility
- Group must have `superdogs_enabled = true`
- Game's `spread` (after rounding) must be `>= 6.5` (absolute value)
- User must have fewer than `superdogs_per_user` superdogs used in this challenge
- Backend validates all three conditions on pick submission; return 422 with a clear, specific error message for each failure case

### Pick Visibility
- Controlled by the group's `blind_picks` flag
- `GET /picks` for a week always returns the requesting user's own picks
- If `blind_picks = true`: other users' picks are omitted from the response for any game where `kickoff_at > now()`. After kickoff, all picks become visible.
- If `blind_picks = false`: all group members' picks are returned regardless of kickoff time
- Visibility is enforced server-side — picks for locked games are not included in the response payload at all, not merely hidden in the client

### Result Processing (triggered by `/dev/mock-results` in dev, or by a scheduled Odds API results fetch in prod)
1. Record `home_score` and `away_score` on the game
2. Determine winner against the spread using `spread` (not raw)
3. For each pick on that game:
   - If `is_superdog = true`: check if underdog won outright → `superdog_win`; else `loss`
   - Otherwise: compare picked team cover → `win` or `loss`
4. Update `standings` for each affected user in the group
5. Set `result_posted = true` on the game
6. Trigger FCM result notification to all group members

### Notification Scheduling
- When a week/slate is created, schedule an APScheduler job to notify the admin to finalize the slate at T-180min before the first game kickoff of that slate
- When a game is added to a slate, schedule APScheduler pick-reminder jobs at T-120min, T-60min, T-30min, T-15min before that game's kickoff. At each interval, query group members (including the admin) who have no pick for that game yet → send FCM alert
- When results are processed, send a silent FCM data message (not an alert) to all group members to trigger iOS cache invalidation and re-fetch
- When the admin finalizes a slate, send a silent FCM data message to all group members to trigger iOS cache invalidation and re-fetch
- Cancel scheduled jobs if a game is removed from the slate or its kickoff time changes

---

## iOS Repository Protocol Example

```swift
/// Protocol defining all game-related data access.
/// Implementations: LiveGameRepository, MockGameRepository (local), MockBackendGameRepository (dev server)
protocol GameRepositoryProtocol {
    /// Fetches all games for a given week slate, including the current user's pick state.
    /// - Parameters:
    ///   - groupID: The group whose slate to fetch.
    ///   - weekID: The specific week/slate identifier.
    /// - Returns: Array of `Game` domain models with embedded pick state.
    func fetchGames(groupID: String, weekID: String) async throws -> [Game]

    /// Fetches available odds from the backend for admin slate building.
    /// - Parameters:
    ///   - sport: The sport key (e.g. "americanfootball_nfl")
    ///   - dateRange: Optional date range filter.
    func fetchAvailableOdds(sport: Sport, dateRange: ClosedRange<Date>?) async throws -> [Game]
}
```

All repository protocols follow this pattern. `AppDependencies.swift` is the single place where concrete implementations are instantiated and injected, controlled by a build scheme environment variable:

```swift
// AppDependencies.swift
#if MOCK_LOCAL
let gameRepo: GameRepositoryProtocol = MockGameRepository()
#elseif MOCK_BACKEND
let gameRepo: GameRepositoryProtocol = MockBackendGameRepository(baseURL: devServerURL)
#else
let gameRepo: GameRepositoryProtocol = LiveGameRepository(networkService: networkService)
#endif
```

---

## FastAPI Dependency Injection Pattern

```python
# Example of a protected endpoint using FastAPI Depends()
@router.post("/picks", response_model=PickRead, status_code=201)
async def submit_pick(
    pick_in: PickCreate,
    current_user: User = Depends(get_current_user),   # JWT validation
    db: Session = Depends(get_db),                     # DB session
    env: Settings = Depends(get_settings)              # App config
) -> Pick:
    """
    Submit a pick for a game.

    - Validates the game exists and has not yet kicked off.
    - Validates superdog eligibility if is_superdog=True (group must have superdogs_enabled,
      spread must be >= 6.5, and user must be under their superdogs_per_user limit).
    - Returns 422 with detail if any validation fails.
    - Returns 409 if a pick already exists (use PUT /picks/{id} to update).
    """
```

---

## Environment Variables

```bash
# .env.example

APP_ENV=development              # 'development' | 'production'
DATABASE_URL=postgresql+psycopg2://user:pass@host:5432/pickem
SECRET_KEY=your-jwt-secret
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=30
ODDS_API_KEY=your-odds-api-key
ODDS_API_BASE_URL=https://api.the-odds-api.com
ODDS_CACHE_TTL_MINUTES=120       # background re-fetch threshold for /odds/available
FCM_SERVER_KEY=your-fcm-server-key
FCM_PROJECT_ID=your-firebase-project-id
```

---

## General Implementer Notes

- Use Alembic from day one — never manually alter the DB schema
- The Odds API sport key for NFL is `americanfootball_nfl`; for FIFA World Cup it is `soccer_fifa_world_cup`
- The Odds API `spreads` market returns `point` (the spread value) and `price` (the juice) per outcome — only `point` is needed
- FCM HTTP v1 API requires a Google service account OAuth2 token, not just a server key — handle token refresh in `notifications.py`
- All timestamps stored and returned as UTC; iOS formats for local display
- Join codes should be 6-character alphanumeric, uppercase, regeneratable by admin
- Superdog availability is driven purely by the group's `superdogs_enabled` flag — applies to both Season and World Cup modes, though World Cup spreads are typically too tight to qualify (spread must be >= 6.5)
- `ODDS_CACHE_TTL_MINUTES` should be a configurable env variable (default 120) controlling when `GET /odds/available` triggers a background re-fetch

### Backend
- Unit tests for spread rounding logic (edge cases: exactly `.0`, already `.5`, negative spreads)
- Unit tests for result processing logic (win/loss/superdog permutations)
- Unit tests for pick visibility rules
- Integration tests for all endpoints using FastAPI `TestClient` with a test DB
- Test that `/dev/*` endpoints return 404 when `APP_ENV=production`

### iOS
- Unit tests for `Game` domain model spread rounding and superdog eligibility computed properties
- Unit tests for all ViewModels using `MockGameRepository` / `MockPickRepository`
- Unit tests for DTO → Domain Model mapping
- SwiftUI Previews should use `LocalMockRepository` exclusively

---

## Build Order

The intended implementation sequence is:

### Phase 1 — iOS with Local Mock Data
Build the full iOS app against `LocalMockRepository`. All screens, navigation, ViewModels, and domain logic should be complete and unit tested before any backend work begins. SwiftUI previews should be fully functional. No network calls are made in this phase.

### Phase 2 — Backend with Mock Data
Build the full FastAPI backend with `APP_ENV=development`. Use `/dev/mock-games` and `/dev/mock-results` to drive all development and testing. All endpoints, auth, business logic, and the result processing pipeline should be complete before connecting to the Odds API. iOS switches to `MockBackendRepository` to validate against the real API contract.

### Phase 3 — Backend with Live Odds API
Replace mock game seeding with live Odds API integration. Validate spread rounding, scheduler jobs, and odds cache refresh against real data. iOS remains on `MockBackendRepository` or switches to `LiveRepository` for end-to-end testing.

### Phase 4 — Integration & Production
Full `LiveRepository` on iOS against the deployed Fly.io backend. FCM push notifications, APNs setup, and production environment configuration.

---

## README Requirements

Each repository (`PickEm-iOS/` and `pickem-api/`) must include a thorough `README.md` covering the following. These must be kept up to date as the project evolves.

### `pickem-api/README.md` must include:
- **Prerequisites** — Python version, Fly.io CLI, Docker, PostgreSQL (local or Fly.io)
- **Local development setup** — step-by-step: clone, create virtualenv, `pip install -r requirements.txt`, copy `.env.example` to `.env`
- **Environment variable reference** — every variable in `.env.example` explained: what it is, where to get it, what the default is, whether it is required in dev vs prod
- **Database setup** — how to provision a local Postgres instance, run `alembic upgrade head`, and verify the schema
- **Running in dev mode** — `APP_ENV=development uvicorn app.main:app --reload`, confirming `/dev/` endpoints are live
- **Seeding mock data** — example `curl` commands for `POST /dev/mock-games` and `POST /dev/mock-results` with realistic payloads
- **Running tests** — `pytest` command, how to point tests at a separate test DB
- **Odds API setup** — how to register for an API key at the-odds-api.com, which tier is needed, where to put the key, how to verify it works
- **FCM setup** — how to create a Firebase project (FCM only), generate a service account JSON, configure `FCM_PROJECT_ID` and the service account credentials, how to send a test notification
- **Fly.io deployment** — `fly launch`, `fly secrets set`, `fly postgres create`, `fly deploy` step by step
- **Alembic workflow** — how to generate a new migration, apply it locally, apply it on Fly.io

### `PickEm-iOS/README.md` must include:
- **Prerequisites** — Xcode version, iOS deployment target, required capabilities (Push Notifications, Background Fetch)
- **Scheme configuration** — the three build schemes (`MOCK_LOCAL`, `MOCK_BACKEND`, `Live`) and how to switch between them in Xcode
- **Running against local mock data (Phase 1)** — select the `MOCK_LOCAL` scheme, no configuration needed
- **Running against the local backend (Phase 2)** — select `MOCK_BACKEND`, set `DEV_SERVER_URL` in the scheme environment variables to point at the local FastAPI server
- **Running against production (Phase 4)** — select `Live`, set `API_BASE_URL`
- **APNs / FCM setup** — how to register the App ID for push notifications in the Apple Developer portal, download the APNs key, upload it to Firebase, and add `GoogleService-Info.plist` to the project
- **Running tests** — how to run the unit test suite; note that all tests use `LocalMockRepository` and require no network or backend
