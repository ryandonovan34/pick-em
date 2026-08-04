#!/usr/bin/env python3
"""
seed_dev.py — Wipe and fully reseed the development database.

Simulates being partway through the NFL regular season: creates 4 users and
one NFL group ("Sunday Crew", preseason excluded), plays out Weeks 1-8 in
full (deterministic scores + every user's picks — this is just background
history to make the standings look real), then leaves Week 9 (the "current"
week) in a mixed final/live/upcoming state for day-to-day demoing.

Talks to Postgres directly via psycopg2 (no `psql` binary required — the
previous bash version's dependency on `psql` being on PATH was a recurring
source of friction) and to the running dev API via httpx.

Usage:
    cd pickem-api
    # Make sure the dev server is running: APP_ENV=development uvicorn app.main:app --reload
    python scripts/seed_dev.py

Environment (defaults shown):
    API_BASE_URL   http://localhost:8000
    DATABASE_URL   postgresql://localhost/pickem
"""

import os
import random
import sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import httpx
import psycopg2

BASE_URL = os.environ.get("API_BASE_URL", "http://localhost:8000")
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://localhost/pickem")
_EASTERN = ZoneInfo("America/New_York")

SEED = 20260921  # fixed seed -> reproducible mock history across runs
CURRENT_WEEK = 9
COMPLETED_WEEKS = 8
NUM_TEMPLATES = 20  # keep in sync with app/routers/dev.py::_NFL_TEMPLATES

USERS = [
    {"email": "alice@test.com", "display_name": "Alice"},
    {"email": "bob@test.com", "display_name": "Bob"},
    {"email": "charlie@test.com", "display_name": "Charlie"},
    {"email": "diana@test.com", "display_name": "Diana"},
]
PASSWORD = "password123"


# ── Database (direct, bypassing the API — for wipe + backdating only) ────────

def _pg_connect():
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = True
    return conn


def wipe_database() -> None:
    print("▶  Clearing database...")
    conn = _pg_connect()
    with conn.cursor() as cur:
        cur.execute(
            "TRUNCATE picks, standings, slate_games, games, weeks, "
            "group_members, groups, refresh_tokens, users CASCADE;"
        )
    conn.close()
    print("   Done")


def backdate_games(kickoffs: dict[str, datetime]) -> None:
    """
    Move already-created games into the past. Games must be seeded with a
    near-future kickoff and have their picks submitted BEFORE calling this —
    POST /picks rejects any pick where kickoff_at <= now, so backdating first
    would make every pick submission 400.
    """
    conn = _pg_connect()
    with conn.cursor() as cur:
        for game_id, kickoff in kickoffs.items():
            cur.execute("UPDATE games SET kickoff_at = %s WHERE id = %s", (kickoff, game_id))
    conn.close()


def resync_week_window(week_id: str) -> None:
    """
    Recompute a week's starts_on/ends_on from the CURRENT kickoff_at of every
    game presently linked to it (mirrors auto_slate.py's
    _recompute_week_window). Needed because get_or_create_week() computes the
    window once at seed time from the games' original near-future kickoffs;
    backdate_games() moves some (or all) of those kickoffs afterward via raw
    SQL, so the window would otherwise go stale — e.g. Week 9 only backdates
    2 of its 4 games (the other 2 stay upcoming), so the window must be
    re-derived from all 4, not just the backdated pair.
    """
    conn = _pg_connect()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT g.kickoff_at FROM games g "
            "JOIN slate_games sg ON sg.game_id = g.id "
            "WHERE sg.week_id = %s",
            (week_id,),
        )
        # ET calendar date, not the raw UTC date — an 8+ PM ET kickoff
        # (Sunday/Monday night football) is already the next day in UTC.
        dates = [row[0].astimezone(_EASTERN).date() for row in cur.fetchall()]
        if dates:
            starts_on = min(dates) - timedelta(days=min(dates).weekday())
            last_day = max(dates)
            # +7, not +6: a standard NFL week runs Thursday through the
            # FOLLOWING Monday (MNF), which is always +7 days from a
            # Monday-anchored starts_on — matches games.py::_week_end.
            ends_on = last_day if last_day > starts_on + timedelta(days=7) else None
            cur.execute(
                "UPDATE weeks SET starts_on = %s, ends_on = %s WHERE id = %s",
                (starts_on, ends_on, week_id),
            )
    conn.close()


# ── API helpers ────────────────────────────────────────────────────────────────

def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def register(client: httpx.Client, email: str, display_name: str) -> str:
    resp = client.post("/auth/register", json={
        "email": email, "display_name": display_name, "password": PASSWORD,
    })
    resp.raise_for_status()
    return resp.json()["access_token"]


def create_group(client: httpx.Client, token: str) -> dict:
    resp = client.post("/groups", headers=_auth(token), json={
        "name": "Sunday Crew",
        "sport": "americanfootball_nfl",
        "mode": "season",
        "season_year": datetime.now(timezone.utc).year,
        "blind_picks": False,
        "superdogs_enabled": True,
        "superdogs_per_user": 3,
        "include_preseason": False,
        "include_playoffs": True,
    })
    resp.raise_for_status()
    return resp.json()


def join_group(client: httpx.Client, token: str, join_code: str) -> None:
    resp = client.post("/groups/join", headers=_auth(token), json={"join_code": join_code})
    resp.raise_for_status()


def seed_week(
    client: httpx.Client, group_id: str, week_number: int, template_offset: int, game_count: int = 4,
) -> dict:
    resp = client.post("/dev/seed-week", json={
        "group_id": group_id,
        "sport": "americanfootball_nfl",
        "game_count": game_count,
        "week_number": week_number,
        "template_offset": template_offset,
    })
    resp.raise_for_status()
    return resp.json()


def submit_pick(
    client: httpx.Client, token: str, game_id: str, group_id: str, picked_team: str, is_superdog: bool = False,
) -> None:
    resp = client.post("/picks", headers=_auth(token), json={
        "game_id": game_id, "group_id": group_id,
        "picked_team": picked_team, "is_superdog": is_superdog,
    })
    resp.raise_for_status()


def post_result(client: httpx.Client, game_id: str, home_score: int, away_score: int) -> None:
    resp = client.post("/dev/mock-results", json={
        "game_id": game_id, "home_score": home_score, "away_score": away_score,
    })
    resp.raise_for_status()


# ── Realistic NFL weekly scheduling ─────────────────────────────────────────────
# Duplicated from app/services/nfl_calendar.py (thursday_of / weekly_slot_kickoff)
# rather than imported — this script deliberately only talks to Postgres and the
# HTTP API, never the app package directly, matching simulate_score() below.

def _et(d, hour: int, minute: int) -> datetime:
    """Local Eastern Time wall-clock -> UTC. DST-aware (season spans EDT and EST)."""
    return datetime(d.year, d.month, d.day, hour, minute, tzinfo=_EASTERN).astimezone(timezone.utc)


def thursday_of(d):
    """The Thursday on/before d — the kickoff day of the NFL week containing d."""
    return d - timedelta(days=(d.weekday() - 3) % 7)


def weekly_slot_kickoff(thursday, slot_index: int, slot_count: int, week_number: int | None = None) -> datetime:
    """Thursday Night Football, Sunday's early/late windows, and an
    alternating SNF/MNF closer — see nfl_calendar.weekly_slot_kickoff."""
    sunday = thursday + timedelta(days=3)
    monday = thursday + timedelta(days=4)
    if slot_index == 0:
        return _et(thursday, 20, 15)
    if slot_count >= 2 and slot_index == slot_count - 1:
        if (week_number or 0) % 2 == 0:
            return _et(monday, 20, 15)
        return _et(sunday, 20, 20)
    if slot_count >= 3 and slot_index == slot_count - 2:
        return _et(sunday, 16, 25)
    return _et(sunday, 13, 0)


# ── Deterministic score generation ──────────────────────────────────────────────

def simulate_score(rng: random.Random, spread: float) -> tuple[int, int]:
    """
    spread is the HOME team's spread — always negative in our mock templates
    (see dev.py::_NFL_TEMPLATES), so home is always favored by abs(spread).
    Returns (home_score, away_score).
    """
    margin = abs(spread)
    base = rng.randint(14, 28)
    roll = rng.random()
    if roll < 0.55:
        home = base + int(margin) + rng.randint(1, 10)   # favorite covers
        away = base
    elif roll < 0.85:
        bump = max(1, int(margin) - 1)
        home = base + rng.randint(1, bump)                # favorite wins, doesn't cover
        away = base
    else:
        away = base + rng.randint(1, 14)                   # underdog wins outright
        home = base
    return home, away


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    rng = random.Random(SEED)
    now = datetime.now(timezone.utc)

    wipe_database()

    with httpx.Client(base_url=BASE_URL, timeout=10.0) as client:
        print("▶  Registering users...")
        tokens: dict[str, str] = {
            u["display_name"]: register(client, u["email"], u["display_name"]) for u in USERS
        }
        print("   " + "  ".join(u["email"] for u in USERS))

        print("▶  Creating group...")
        group = create_group(client, tokens["Alice"])
        group_id, join_code = group["id"], group["join_code"]
        print(f"   NFL 'Sunday Crew'   {group_id}  join: {join_code}")

        print("▶  Adding members...")
        for name in ("Bob", "Charlie", "Diana"):
            join_group(client, tokens[name], join_code)
        print("   Bob, Charlie, Diana joined the group")

        # ── Weeks 1-8: fully played out, deterministic ─────────────────────────
        for week_number in range(1, COMPLETED_WEEKS + 1):
            print(f"▶  Week {week_number} — seeding...")
            template_offset = ((week_number - 1) * 4) % NUM_TEMPLATES
            week_data = seed_week(client, group_id, week_number, template_offset)
            games = week_data["games"]

            print(f"▶  Week {week_number} — submitting picks...")
            for game in games:
                favorite = game["favorite_team"]
                underdog = game["away_team"] if favorite == game["home_team"] else game["home_team"]
                for name in tokens:
                    picked_team = favorite if rng.random() < 0.6 else underdog
                    submit_pick(client, tokens[name], game["id"], group_id, picked_team)

            print(f"▶  Week {week_number} — backdating kickoffs...")
            week_thursday = thursday_of(now.date()) - timedelta(weeks=CURRENT_WEEK - week_number)
            backdate_games({
                game["id"]: weekly_slot_kickoff(week_thursday, i, len(games), week_number)
                for i, game in enumerate(games)
            })
            resync_week_window(week_data["week"]["id"])

            print(f"▶  Week {week_number} — posting results...")
            for game in games:
                home, away = simulate_score(rng, game["spread"])
                post_result(client, game["id"], home, away)

        # ── Week 9 (current): final / live / upcoming mix ──────────────────────
        print(f"▶  Week {CURRENT_WEEK} — seeding...")
        w9 = seed_week(client, group_id, CURRENT_WEEK, template_offset=4)  # Ravens/Bengals/Lions/Packers
        games_by_home = {g["home_team"]: g for g in w9["games"]}
        ravens = games_by_home["Baltimore Ravens"]
        bengals = games_by_home["Cincinnati Bengals"]
        lions = games_by_home["Detroit Lions"]
        # Packers -2.5 vs Vikings intentionally gets zero picks (upcoming, empty state).

        print(f"▶  Week {CURRENT_WEEK} — submitting picks...")
        # Ravens -9.5 vs Browns (will be finalized)
        submit_pick(client, tokens["Alice"], ravens["id"], group_id, "Baltimore Ravens")
        submit_pick(client, tokens["Bob"], ravens["id"], group_id, "Cleveland Browns")
        submit_pick(client, tokens["Charlie"], ravens["id"], group_id, "Baltimore Ravens")
        submit_pick(client, tokens["Diana"], ravens["id"], group_id, "Baltimore Ravens")

        # Bengals -3.5 vs Steelers (will become live — Diana skips this one)
        submit_pick(client, tokens["Alice"], bengals["id"], group_id, "Cincinnati Bengals")
        submit_pick(client, tokens["Bob"], bengals["id"], group_id, "Pittsburgh Steelers")
        submit_pick(client, tokens["Charlie"], bengals["id"], group_id, "Cincinnati Bengals")

        # Lions -7.5 vs Bears (upcoming — early picks from Alice and Bob only)
        submit_pick(client, tokens["Alice"], lions["id"], group_id, "Detroit Lions")
        submit_pick(client, tokens["Bob"], lions["id"], group_id, "Chicago Bears")

        print(f"▶  Week {CURRENT_WEEK} — finalizing Ravens, setting Bengals live...")
        # Deliberately NOT using weekly_slot_kickoff here: these two need to be
        # guaranteed in the past (final / live) no matter what day or time this
        # script actually runs, which a fixed slot (e.g. "next Thursday 8:15 PM
        # ET") can't promise. Lions/Packers below don't have that constraint —
        # they keep the realistic Sun 4:25 PM / SNF-MNF slots seed_week() already
        # assigned them at creation time.
        backdate_games({
            ravens["id"]: now - timedelta(hours=27),
            bengals["id"]: now - timedelta(minutes=90),
        })
        # Lions/Packers stay at their original near-future kickoff — resync
        # from ALL 4 games (not just the 2 just backdated) so the week's
        # window correctly spans from the already-played Ravens game to the
        # still-upcoming Packers game, same as a real in-progress NFL week.
        resync_week_window(w9["week"]["id"])
        post_result(client, ravens["id"], 27, 10)

        # ── Summary ──────────────────────────────────────────────────────────────
        standings_resp = client.get(f"/groups/{group_id}/standings", headers=_auth(tokens["Alice"]))
        standings_resp.raise_for_status()

        print()
        print("Seed complete.")
        print()
        print("Test accounts (password: password123)")
        print("  " + "    ".join(u["email"] for u in USERS))
        print()
        print(f"NFL 'Sunday Crew'      join code: {join_code}")
        print(f"  Weeks 1-{COMPLETED_WEEKS}  fully played out")
        print(f"  Week {CURRENT_WEEK}  Ravens final | Bengals/Steelers LIVE | Lions/Packers upcoming")
        print("  Standings:")
        for s in standings_resp.json():
            print(f"    {s['display_name']:<10} {s['record']:>6}  {s['win_percentage'] * 100:5.1f}%")


if __name__ == "__main__":
    try:
        main()
    except httpx.ConnectError:
        print(
            f"Could not reach the API at {BASE_URL}. Is the dev server running?\n"
            "  APP_ENV=development uvicorn app.main:app --reload",
            file=sys.stderr,
        )
        sys.exit(1)
    except httpx.HTTPStatusError as e:
        print(f"Request failed: {e.request.method} {e.request.url} -> {e.response.status_code}\n{e.response.text}",
              file=sys.stderr)
        sys.exit(1)
