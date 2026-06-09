# PickEm API

FastAPI backend for the PickEm sports pick'em challenge app.  
Supports NFL season picks and FIFA World Cup 2026 picks against the spread.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.12+ | Install via [pyenv](https://github.com/pyenv/pyenv) or [Homebrew](https://brew.sh): `brew install python@3.13` |
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

`scripts/seed_dev.sh` wipes the database and builds a complete realistic dataset in one shot. Run it any time you want a clean, known state.

```bash
# From the pickem-api directory, with the server running:
./scripts/seed_dev.sh

# Override defaults if needed:
DATABASE_URL=postgresql://localhost/pickem API_BASE_URL=http://localhost:8000 ./scripts/seed_dev.sh
```

**What it creates:**

| | NFL — Sunday Crew | World Cup 2026 |
|---|---|---|
| **Members** | Alice (admin), Bob, Charlie, Diana | same 4 |
| **Settings** | blind_picks off, superdogs on (3/user) | blind_picks on, superdogs off |
| **Past week** | Week 11 — 4 games, all final | Matchday 1 — 4 games, all final |
| **Current week** | Week 12 | Matchday 2 |
| ↳ Final | Ravens 27-10 Browns | Germany 2-0 Japan |
| ↳ Live | Bengals vs Steelers (kicked off) | Spain vs Costa Rica (kicked off) |
| ↳ Upcoming | Lions vs Bears · Packers vs Vikings | Portugal vs Ghana · England vs Iran |

**Test accounts** (password: `password123`):

| Email | Display name |
|-------|-------------|
| `alice@test.com` | Alice (admin) |
| `bob@test.com` | Bob |
| `charlie@test.com` | Charlie |
| `diana@test.com` | Diana |

**Expected standings after seed:**

NFL Sunday Crew:
```
1. Alice    3W-1L  1SD   85.7%
2. Charlie  4W-1L        80.0%
3. Diana    3W-2L        60.0%
4. Bob      2W-3L        40.0%
```

World Cup 2026:
```
1. Alice    4W-1L        80.0%
2. Diana    4W-1L        80.0%
3. Bob      3W-2L        60.0%
4. Charlie  2W-3L        40.0%
```

> The script requires `psql` to be on your PATH (used to set "live" game kickoff times and to wipe the DB). It uses `DATABASE_URL` with the same default as the server.

### Individual dev endpoints

```bash
# Seed games into the odds pool (kickoff 48h from now)
curl -X POST http://localhost:8000/dev/mock-games \
  -H "Content-Type: application/json" \
  -d '{"sport": "americanfootball_nfl", "week_label": "Week 12", "game_count": 4}'

# Create a week and populate it in one shot
curl -X POST http://localhost:8000/dev/seed-week \
  -H "Content-Type: application/json" \
  -d '{"group_id": "GROUP_ID", "sport": "americanfootball_nfl", "week_label": "Week 12", "game_count": 4}'

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
3. The sport keys used by this app:
   - NFL: `americanfootball_nfl`
   - World Cup: `soccer_fifa_world_cup`
4. To verify the key works:
   ```bash
   curl "https://api.the-odds-api.com/v4/sports?apiKey=YOUR_KEY"
   ```

---

## FCM Setup (Phase 4)

Push notifications use Firebase Cloud Messaging (FCM HTTP v1 API — **not** the legacy server key).

1. Go to [Firebase Console](https://console.firebase.google.com) → Add project → no Analytics needed.
2. Project settings → Service accounts → Generate new private key → download the JSON file.
3. Set `FCM_PROJECT_ID=your-project-id` in `.env`.
4. Set `FCM_SERVICE_ACCOUNT_JSON=/path/to/key.json` (or paste the JSON as a string).
5. To send a test notification, implement `send_pick_reminder` in `app/services/notifications.py` and call it manually.

---

## Fly.io Deployment

```bash
# One-time setup
fly auth login
fly launch --name pickem-api --region iad --no-deploy
fly postgres create --name pickem-db --region iad

# Attach the DB (sets DATABASE_URL secret automatically)
fly postgres attach pickem-db

# Set remaining secrets
fly secrets set SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
fly secrets set APP_ENV=production

# Deploy
fly deploy

# Run Alembic migrations on the production DB
fly ssh console -C "alembic upgrade head"
```

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
