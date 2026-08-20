# PickEm API

FastAPI backend for the PickEm NFL pick'em challenge app.  
Supports NFL season picks against the spread.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.13 | Matches the production Docker image (`python:3.13-slim`). Install via [pyenv](https://github.com/pyenv/pyenv) or [Homebrew](https://brew.sh): `brew install python@3.13` |
| PostgreSQL | 15+ | Local: `brew install postgresql@15`; or use Docker |
| Fly.io CLI | latest | `brew install flyctl` — required for deployment only |
| Docker | any | Required for deployment only |

---

## Local Development Setup

```bash
# 1. Clone and enter the directory
cd pickem-api

# 2. Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Copy the example env file and fill in your values
cp .env.example .env
# Edit .env — at minimum set DATABASE_URL and SECRET_KEY
```

---

## Environment Variable Reference

All variables live in `.env`. Never commit this file.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `APP_ENV` | Yes | `development` | `development` enables `/dev/*` endpoints and auto-creates tables on startup. Set to `production` in Fly.io. |
| `DATABASE_URL` | Yes | `postgresql+psycopg2://postgres:postgres@localhost:5432/pickem` | Full SQLAlchemy connection string. |
| `SECRET_KEY` | Yes | `change-me-before-production` | Random string used to sign JWT tokens. Generate: `python -c "import secrets; print(secrets.token_hex(32))"` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | No | `30` | How long a JWT access token is valid. |
| `REFRESH_TOKEN_EXPIRE_DAYS` | No | `30` | How long a refresh token is valid. |
| `ODDS_API_KEY` | Phase 3+ | *(blank)* | API key from [the-odds-api.com](https://the-odds-api.com). Leave blank in Phase 2. |
| `ODDS_API_BASE_URL` | No | `https://api.the-odds-api.com` | Odds API base URL. |
| `ODDS_CACHE_TTL_MINUTES` | No | `120` | If cached odds are older than this, a background re-fetch is triggered when an admin views available games. |
| `FCM_PROJECT_ID` | Phase 4+ | *(blank)* | Firebase project ID for push notifications. |
| `FCM_SERVICE_ACCOUNT_JSON` | Phase 4+ | *(blank)* | Path to or raw JSON content of the Firebase service account credentials. |

---

## Database Setup

### Start a local PostgreSQL instance

Using Homebrew:
```bash
brew services start postgresql@15
createdb pickem
```

Using Docker:
```bash
docker run -d \
  --name pickem-postgres \
  -e POSTGRES_DB=pickem \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  postgres:15
```

### Apply migrations

```bash
# Upgrade to the latest schema
alembic upgrade head

# Verify the tables were created
psql pickem -c "\dt"
```

---

## Running in Dev Mode

```bash
# Make sure APP_ENV=development in .env
uvicorn app.main:app --reload
```

The server starts at **http://localhost:8000**.  
Interactive API docs: **http://localhost:8000/docs**  
(Docs are disabled in production.)

In development mode, the server automatically creates all database tables on startup — no need to run Alembic first for a quick start. Use Alembic for all schema changes going forward.

---

## Seeding Mock Data (Phase 2)

The `/dev/*` endpoints let you drive the full app without the Odds API.

### Full dev seed script

`scripts/seed_dev.py` wipes the database and simulates being partway through the NFL season in one shot: Weeks 1-8 are fully played out (deterministic scores + every user's picks — reproducible run to run via a fixed random seed), and Week 9 (the "current" week) is left in a mixed final/live/upcoming state for day-to-day demoing. Run it any time you want a clean, known state.

Talks to Postgres directly via `psycopg2` (no `psql` binary required) and to the running dev API via `httpx` — both are already in `requirements.txt`.

```bash
# From the pickem-api directory, with the server running:
python scripts/seed_dev.py

# Override defaults if needed:
DATABASE_URL=postgresql://localhost/pickem API_BASE_URL=http://localhost:8000 python scripts/seed_dev.py
```

**What it creates:**

| | NFL — Sunday Crew |
|---|---|
| **Members** | Alice (admin), Bob, Charlie, Diana |
| **Settings** | blind_picks off, superdogs on (3/user), preseason excluded, playoffs included |
| **Weeks 1-8** | Fully played out — 4 games each, all final, every member picked every game |
| **Week 9 (current)** | Ravens final (27-10) · Bengals/Steelers live (kicked off, no result) · Lions/Bears and Packers/Vikings upcoming |

**Test accounts** (password: `password123`):

| Email | Display name |
|-------|-------------|
| `alice@test.com` | Alice (admin) |
| `bob@test.com` | Bob |
| `charlie@test.com` | Charlie |
| `diana@test.com` | Diana |

**Expected standings after seed** (through Week 8 — Week 9's only posted result, Ravens, is reflected too):

```
Diana       20-13   60.6%
Bob         19-14   57.6%
Charlie     18-15   54.5%
Alice       16-17   48.5%
```

### Individual dev endpoints

```bash
# Seed games into the odds pool (kickoff 48h from now)
curl -X POST http://localhost:8000/dev/mock-games \
  -H "Content-Type: application/json" \
  -d '{"sport": "americanfootball_nfl", "week_label": "Week 12", "game_count": 4}'

# Create/reuse a week (by NFL week number, -4..-1 for the 4 preseason weeks)
# and populate it in one shot. week_label and week_number are both optional —
# omit week_label to auto-derive it (e.g. "Week 9", "Preseason Week 1",
# "Wild Card") from week_number.
curl -X POST http://localhost:8000/dev/seed-week \
  -H "Content-Type: application/json" \
  -d '{"group_id": "GROUP_ID", "sport": "americanfootball_nfl", "week_number": 9, "game_count": 4}'

# Post a result (triggers full scoring + standings pipeline)
curl -X POST http://localhost:8000/dev/mock-results \
  -H "Content-Type: application/json" \
  -d '{"game_id": "GAME_ID", "home_score": 27, "away_score": 14}'

# View available team templates
curl http://localhost:8000/dev/mock-templates
```

---

## Running Tests

```bash
pytest                    # run all tests
pytest -v                 # verbose output
pytest tests/test_spread_rounding.py  # run a specific file
pytest -k "test_login"    # run tests matching a keyword
```

Tests use an isolated SQLite database (`test.db`) so they never touch your local PostgreSQL. The file is created and dropped per test.

---

## Odds API Setup (Phase 3)

1. Register at [the-odds-api.com](https://the-odds-api.com) — the **free tier** (500 requests/month) is enough for development and testing.
2. Copy your API key and set `ODDS_API_KEY=your_key` in `.env`.
3. The app's internal/group-facing sport key is `americanfootball_nfl`, but this fans out to **two** real Odds API sport keys under the hood (see `odds_api_sport_keys` in `app/services/odds.py`), since the Odds API splits NFL into separate endpoints per phase of the season:
   - `americanfootball_nfl` — regular season + playoffs
   - `americanfootball_nfl_preseason` — preseason only

   Every game ends up stored under the same internal `sport='americanfootball_nfl'` regardless of which real endpoint it came from, so a group's sport filter doesn't need to care about the split.
4. To verify the key works:
   ```bash
   curl "https://api.the-odds-api.com/v4/sports?apiKey=YOUR_KEY"
   ```

See **Background Jobs & Caching** below for exactly when and how often the app calls out to this API — it's not just "on demand."

---

## Authentication

JWT access tokens + opaque refresh tokens (`app/auth/`):

1. `POST /auth/register` or `POST /auth/login` returns both an **access token** (a signed JWT, `ACCESS_TOKEN_EXPIRE_MINUTES` — default 30 min) and a **refresh token** (a random opaque UUID string, `REFRESH_TOKEN_EXPIRE_DAYS` — default 30 days).
2. Every authenticated request sends the access token as `Authorization: Bearer <token>`. `get_current_user` (`app/auth/dependencies.py`) decodes and validates it, then loads the `User` row — 401 if missing/invalid/expired, 404 if the user was deleted after the token was issued.
3. When the access token expires, the client calls `POST /auth/refresh` with the refresh token to get a new access token. **The refresh token itself is not rotated** — it stays valid until it expires or `POST /auth/logout` is called.
4. Refresh tokens are never stored in plaintext: only their bcrypt hash is persisted (`RefreshToken.token_hash`), so a database leak doesn't hand out usable tokens. Login is checked against a dummy bcrypt hash even when the email doesn't exist, so the response timing doesn't leak whether an account exists.
5. Logout deletes the matching `RefreshToken` row — this is why refresh tokens use random opaque values instead of JWTs: a stateless JWT refresh token couldn't be revoked without a separate blocklist.

---

## Background Jobs & Caching

All background work runs via APScheduler (`app/services/scheduler.py`), starting in-process when the app boots (`main.py`'s `lifespan`) and stopping on shutdown. **Jobs live in memory only** — nothing is persisted, so a redeploy or a Fly.io machine suspend/resume wipes any pending job.

The startup ingest, 24h interval refresh, and 30-min results poll self-heal automatically since `start()` unconditionally reschedules them on every boot. The two **per-game** jobs (pick reminders and the per-game pre-kickoff refresh/lock) do not: they're scheduled once, tied to a specific future `run_date`, with no re-hydration logic on startup — if the process restarts between when one was scheduled and its fire time, that specific job is simply lost. A pick reminder is recovered the next time that slate changes (which reschedules the whole week); a missed spread lock just means the line stays whatever it last was, unlocked, until the game's own results are processed.

### When the Odds API actually gets called

| Trigger | Cadence | What it does |
|---|---|---|
| App startup | Once | Ingests the full odds pool immediately so a cold start isn't empty. |
| Recurring interval | Every 24h | Refills the odds pool for both real sport keys (see Odds API Setup above). |
| `GET /odds/available` (admin browsing games to add) | On demand, rate-limited by `ODDS_CACHE_TTL_MINUTES` (default 120) | If the newest `Game.odds_fetched_at` for that sport is older than the TTL, a re-fetch is triggered — synchronously if the pool is completely empty (`MISS:cold`), or in a background task while stale data is returned immediately otherwise (`MISS:stale`). Fresh data returns `HIT` and triggers nothing. Check the `X-Cache` response header to see which happened. |
| Per-game pre-kickoff refresh | Once per game, 30 minutes before **that game's own** kickoff | Scheduled the moment an admin adds the game to a slate (`schedule_odds_refresh_for_game`). One last fetch, then the game's spread is **locked** (see below) — this is also why a slate spanning Thursday–Monday doesn't rely on the 24h interval job alone for the later games. No-op if `ODDS_API_KEY` isn't set. |
| Results polling | Every 30 min | Queries the Odds API scores endpoint, but only for the real sport key(s) actually needed — if no slate game with a past kickoff is still pending a result, nothing is queried at all. |

### Spread locking

A game's `spread`/`favorite_team` are freely overwritten by every refresh above — **until** the per-game T-30 refresh fires, which sets `Game.spread_locked = True`. From that point on, `ingest_odds` refuses to touch that game's line again, even if a later poll would otherwise have moved it. This exists so a member's pick is graded against the same number they actually saw, instead of whatever the line drifted to by kickoff.

### Other scheduled jobs

- **Pick reminders** (T-120/60/30/15 before kickoff): scheduled per slate change, not per game — games kicking off within 90 minutes of each other share one digest notification per offset instead of each generating their own set, to avoid a burst of near-duplicate pushes for a tightly-packed slate.
- **Slate admin reminder** (T-180 before a week's first kickoff): nudges the admin if the slate isn't finalized yet.

---

## FCM Setup (Phase 4)

Push notifications use Firebase Cloud Messaging (FCM HTTP v1 API — **not** the legacy server key).

1. Go to [Firebase Console](https://console.firebase.google.com) → Add project → no Analytics needed.
2. Project settings → Service accounts → Generate new private key → download the JSON file.
3. Set `FCM_PROJECT_ID=your-project-id` in `.env`.
4. Set `FCM_SERVICE_ACCOUNT_JSON=/path/to/key.json` (or paste the JSON as a string).
5. To send a test notification: log in as a user who has an `fcm_token` on file (the app calls `PUT /auth/fcm-token` on every launch), then `POST /auth/test-notification` with that user's access token. Returns 409 if the user has no token registered.

---

## Fly.io Deployment

```bash
# One-time setup
fly auth login
fly launch --name pickem-api --region iad --no-deploy
fly postgres create --name pickem-api-db --region iad

# Attach the DB (sets DATABASE_URL secret automatically)
fly postgres attach pickem-api-db

# Set remaining secrets
fly secrets set SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
fly secrets set APP_ENV=production

# Deploy
fly deploy
```

Migrations run automatically as part of every deploy — `fly.toml` sets `release_command = "alembic upgrade head"`, which Fly runs against the production DB before rolling out the new machine. You don't need to run it by hand. (`fly ssh console -C "alembic upgrade head"` is still there as a manual fallback if you ever need to apply a migration without a full deploy.)

---

## Alembic Workflow

### Create a migration after changing a model

```bash
# Auto-generate based on the diff between your models and the current DB schema
alembic revision --autogenerate -m "add column foo to games"

# Review the generated file in alembic/versions/ before applying
alembic upgrade head
```

### Apply migrations on Fly.io

Happens automatically on every `fly deploy` (see Fly.io Deployment above). Only run this by hand for out-of-band recovery:

```bash
fly ssh console -C "alembic upgrade head"
```

### Check current migration status

```bash
alembic current     # which revision the DB is on
alembic history     # full migration history
```

### Roll back one migration

```bash
alembic downgrade -1
```

> **Never manually `ALTER TABLE` a production database.** Always use Alembic.
