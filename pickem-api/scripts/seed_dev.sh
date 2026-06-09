#!/usr/bin/env bash
#
# seed_dev.sh — Wipe and fully reseed the development database.
#
# Creates 4 users, an NFL group, and a World Cup group. Each group gets a
# completed past week (all games final) and a current week with one final
# game, one live game (kicked off, no result yet), and two upcoming games.
#
# Usage:
#   cd pickem-api
#   ./scripts/seed_dev.sh
#
# Environment (all have defaults):
#   API_BASE_URL   http://localhost:8000
#   DATABASE_URL   postgresql://postgres:postgres@localhost:5432/pickem

set -euo pipefail

BASE="${API_BASE_URL:-http://localhost:8000}"
DB_URL="${DATABASE_URL:-postgresql://localhost/pickem}"

# ── Helpers ───────────────────────────────────────────────────────────────────

_jq() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

# Extract game id from a seed-week response by home team name.
_game_id() {
    local resp="$1" team="$2"
    echo "$resp" | python3 -c \
        "import sys,json; games=json.load(sys.stdin)['games']; print(next(g['id'] for g in games if g['home_team']=='$team'))"
}

# Submit a pick. Superdog is optional, defaults to false.
_pick() {
    local token="$1" game_id="$2" group_id="$3" team="$4" superdog="${5:-false}"
    curl -sf -X POST "$BASE/picks" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{\"game_id\":\"$game_id\",\"group_id\":\"$group_id\",\"picked_team\":\"$team\",\"is_superdog\":$superdog}" \
        >/dev/null
}

# Post a game result (triggers full scoring + standings pipeline).
_result() {
    local game_id="$1" home="$2" away="$3"
    curl -sf -X POST "$BASE/dev/mock-results" \
        -H "Content-Type: application/json" \
        -d "{\"game_id\":\"$game_id\",\"home_score\":$home,\"away_score\":$away}" \
        >/dev/null
}

# Set a game's kickoff 90 minutes in the past so it reads as "live"
# (kicked off, picks locked, no result posted yet).
_set_live() {
    psql -q "$DB_URL" -c \
        "UPDATE games SET kickoff_at = NOW() - INTERVAL '90 minutes' WHERE id = '$1';" \
        >/dev/null
}

# ── 1. Wipe database ──────────────────────────────────────────────────────────

echo "▶  Clearing database..."
psql -q "$DB_URL" \
    -c "TRUNCATE picks, standings, games, weeks, group_members, groups, refresh_tokens, users CASCADE;"
echo "   Done"

# ── 2. Register users ─────────────────────────────────────────────────────────

echo "▶  Registering users..."

ALICE_TOKEN=$(curl -sf -X POST "$BASE/auth/register" \
    -H "Content-Type: application/json" \
    -d '{"email":"alice@test.com","display_name":"Alice","password":"password123"}' \
    | _jq "['access_token']")

BOB_TOKEN=$(curl -sf -X POST "$BASE/auth/register" \
    -H "Content-Type: application/json" \
    -d '{"email":"bob@test.com","display_name":"Bob","password":"password123"}' \
    | _jq "['access_token']")

CHARLIE_TOKEN=$(curl -sf -X POST "$BASE/auth/register" \
    -H "Content-Type: application/json" \
    -d '{"email":"charlie@test.com","display_name":"Charlie","password":"password123"}' \
    | _jq "['access_token']")

DIANA_TOKEN=$(curl -sf -X POST "$BASE/auth/register" \
    -H "Content-Type: application/json" \
    -d '{"email":"diana@test.com","display_name":"Diana","password":"password123"}' \
    | _jq "['access_token']")

echo "   alice@test.com  bob@test.com  charlie@test.com  diana@test.com"

# ── 3. Create groups (Alice is admin of both) ─────────────────────────────────

echo "▶  Creating groups..."

NFL_RESP=$(curl -sf -X POST "$BASE/groups" \
    -H "Authorization: Bearer $ALICE_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Sunday Crew",
        "sport": "americanfootball_nfl",
        "mode": "season",
        "season_year": 2025,
        "blind_picks": false,
        "superdogs_enabled": true,
        "superdogs_per_user": 3
    }')
NFL_GROUP=$(echo "$NFL_RESP" | _jq "['id']")
NFL_CODE=$( echo "$NFL_RESP" | _jq "['join_code']")

WC_RESP=$(curl -sf -X POST "$BASE/groups" \
    -H "Authorization: Bearer $ALICE_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "World Cup 2026",
        "sport": "soccer_fifa_world_cup",
        "mode": "worldCup",
        "season_year": 2026,
        "blind_picks": true,
        "superdogs_enabled": false,
        "superdogs_per_user": 0
    }')
WC_GROUP=$(echo "$WC_RESP" | _jq "['id']")
WC_CODE=$( echo "$WC_RESP" | _jq "['join_code']")

echo "   NFL 'Sunday Crew'   $NFL_GROUP  join: $NFL_CODE"
echo "   WC  'World Cup 2026' $WC_GROUP  join: $WC_CODE"

# ── 4. Bob, Charlie, Diana join both groups ───────────────────────────────────

echo "▶  Adding members..."
for TOKEN in "$BOB_TOKEN" "$CHARLIE_TOKEN" "$DIANA_TOKEN"; do
    curl -sf -X POST "$BASE/groups/join" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"join_code\":\"$NFL_CODE\"}" >/dev/null
    curl -sf -X POST "$BASE/groups/join" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"join_code\":\"$WC_CODE\"}" >/dev/null
done
echo "   Bob, Charlie, Diana joined both groups"

# =============================================================================
# NFL — Sunday Crew
#
# Templates used (spread = favorite's perspective, negative = home favored):
#   Week 11 (past)    templates 1-4: Chiefs, Bills, 49ers, Eagles
#   Week 12 (current) templates 5-8: Ravens, Bengals, Lions, Packers
#
# Week 11 results:
#   Chiefs  -7.5 vs Raiders  : Chiefs  win 31-17 → Chiefs covered (Δ14 > 7.5)
#   Bills   -6.5 vs Dolphins : Dolphins win 24-21 → Dolphins won outright (superdog eligible)
#   49ers   -4.5 vs Cowboys  : Cowboys  win 20-17 → Cowboys won (49ers didn't cover)
#   Eagles -10.5 vs Giants   : Eagles   win 38-7  → Eagles covered (Δ31 > 10.5)
#
# Week 11 pick outcomes:
#   Alice   Chiefs WIN  Dolphins SUPERDOG_WIN  49ers LOSS   Eagles WIN  → 2W 1L 1SD
#   Bob     Raiders LOSS  Bills LOSS           Cowboys WIN  Eagles WIN  → 2W 2L
#   Charlie Chiefs WIN  Dolphins WIN           Cowboys WIN  Giants LOSS → 3W 1L
#   Diana   Raiders LOSS  Bills LOSS           Cowboys WIN  Eagles WIN  → 2W 2L
#
# Week 12:
#   Ravens  -9.5 vs Browns   → FINAL  Ravens 27-10 (Δ17 > 9.5, Ravens covered)
#   Bengals -3.5 vs Steelers → LIVE   (kicked off, result pending)
#   Lions   -7.5 vs Bears    → UPCOMING  Alice→Lions, Bob→Bears picked
#   Packers -2.5 vs Vikings  → UPCOMING  no picks yet
#
# Week 12 pick outcomes (Ravens only):
#   Alice  Ravens WIN  → total 3W 1L 1SD  eff 6/7 = 85.7%  ← 1st
#   Bob    Browns LOSS → total 2W 3L            2/5 = 40.0%  ← 4th
#   Charlie Ravens WIN → total 4W 1L            4/5 = 80.0%  ← 2nd
#   Diana  Ravens WIN  → total 3W 2L            3/5 = 60.0%  ← 3rd
# =============================================================================

echo ""
echo "── NFL ──────────────────────────────────────────────────────────────────────"

# ── NFL Week 11 (past — all final) ───────────────────────────────────────────

echo "▶  NFL Week 11 — seeding..."
W11=$(curl -sf -X POST "$BASE/dev/seed-week" \
    -H "Content-Type: application/json" \
    -d "{\"group_id\":\"$NFL_GROUP\",\"sport\":\"americanfootball_nfl\",\"week_label\":\"Week 11\",\"game_count\":4}")

CHIEFS_ID=$( _game_id "$W11" "Kansas City Chiefs")
BILLS_ID=$(  _game_id "$W11" "Buffalo Bills")
NINERS_ID=$( _game_id "$W11" "San Francisco 49ers")
EAGLES_ID=$( _game_id "$W11" "Philadelphia Eagles")

echo "▶  NFL Week 11 — submitting picks..."

# Chiefs -7.5 vs Raiders
_pick "$ALICE_TOKEN"   "$CHIEFS_ID" "$NFL_GROUP" "Kansas City Chiefs"
_pick "$BOB_TOKEN"     "$CHIEFS_ID" "$NFL_GROUP" "Las Vegas Raiders"
_pick "$CHARLIE_TOKEN" "$CHIEFS_ID" "$NFL_GROUP" "Kansas City Chiefs"
_pick "$DIANA_TOKEN"   "$CHIEFS_ID" "$NFL_GROUP" "Las Vegas Raiders"

# Bills -6.5 vs Dolphins (superdog eligible; Alice superdogs Dolphins)
_pick "$ALICE_TOKEN"   "$BILLS_ID" "$NFL_GROUP" "Miami Dolphins" "true"
_pick "$BOB_TOKEN"     "$BILLS_ID" "$NFL_GROUP" "Buffalo Bills"
_pick "$CHARLIE_TOKEN" "$BILLS_ID" "$NFL_GROUP" "Miami Dolphins"
_pick "$DIANA_TOKEN"   "$BILLS_ID" "$NFL_GROUP" "Buffalo Bills"

# 49ers -4.5 vs Cowboys
_pick "$ALICE_TOKEN"   "$NINERS_ID" "$NFL_GROUP" "San Francisco 49ers"
_pick "$BOB_TOKEN"     "$NINERS_ID" "$NFL_GROUP" "Dallas Cowboys"
_pick "$CHARLIE_TOKEN" "$NINERS_ID" "$NFL_GROUP" "Dallas Cowboys"
_pick "$DIANA_TOKEN"   "$NINERS_ID" "$NFL_GROUP" "Dallas Cowboys"

# Eagles -10.5 vs Giants
_pick "$ALICE_TOKEN"   "$EAGLES_ID" "$NFL_GROUP" "Philadelphia Eagles"
_pick "$BOB_TOKEN"     "$EAGLES_ID" "$NFL_GROUP" "Philadelphia Eagles"
_pick "$CHARLIE_TOKEN" "$EAGLES_ID" "$NFL_GROUP" "New York Giants"
_pick "$DIANA_TOKEN"   "$EAGLES_ID" "$NFL_GROUP" "Philadelphia Eagles"

echo "▶  NFL Week 11 — posting results..."
_result "$CHIEFS_ID"  31 17   # Chiefs covered  (Δ14 > 7.5)
_result "$BILLS_ID"   21 24   # Dolphins won outright → Alice SUPERDOG_WIN, Bob/Diana LOSS
_result "$NINERS_ID"  17 20   # Cowboys won → Alice LOSS, Bob/Charlie/Diana WIN
_result "$EAGLES_ID"  38 7    # Eagles covered (Δ31 > 10.5) → Charlie LOSS

# ── NFL Week 12 (current) ─────────────────────────────────────────────────────

echo "▶  NFL Week 12 — seeding..."
# game_count=8 reuses templates 1-4 (already assigned to Week 11) and creates templates 5-8
W12=$(curl -sf -X POST "$BASE/dev/seed-week" \
    -H "Content-Type: application/json" \
    -d "{\"group_id\":\"$NFL_GROUP\",\"sport\":\"americanfootball_nfl\",\"week_label\":\"Week 12\",\"game_count\":8}")

RAVENS_ID=$(  _game_id "$W12" "Baltimore Ravens")
BENGALS_ID=$( _game_id "$W12" "Cincinnati Bengals")
LIONS_ID=$(   _game_id "$W12" "Detroit Lions")
PACKERS_ID=$( _game_id "$W12" "Green Bay Packers")

echo "▶  NFL Week 12 — submitting picks (all games future at this point)..."

# Ravens -9.5 vs Browns (will be finalized)
_pick "$ALICE_TOKEN"   "$RAVENS_ID" "$NFL_GROUP" "Baltimore Ravens"
_pick "$BOB_TOKEN"     "$RAVENS_ID" "$NFL_GROUP" "Cleveland Browns"
_pick "$CHARLIE_TOKEN" "$RAVENS_ID" "$NFL_GROUP" "Baltimore Ravens"
_pick "$DIANA_TOKEN"   "$RAVENS_ID" "$NFL_GROUP" "Baltimore Ravens"

# Bengals -3.5 vs Steelers (will become live — submit picks before moving kickoff)
_pick "$ALICE_TOKEN"   "$BENGALS_ID" "$NFL_GROUP" "Cincinnati Bengals"
_pick "$BOB_TOKEN"     "$BENGALS_ID" "$NFL_GROUP" "Pittsburgh Steelers"
_pick "$CHARLIE_TOKEN" "$BENGALS_ID" "$NFL_GROUP" "Cincinnati Bengals"
# Diana skips this one

# Lions -7.5 vs Bears (upcoming — early picks from Alice and Bob)
_pick "$ALICE_TOKEN" "$LIONS_ID" "$NFL_GROUP" "Detroit Lions"
_pick "$BOB_TOKEN"   "$LIONS_ID" "$NFL_GROUP" "Chicago Bears"

# Packers -2.5 vs Vikings (upcoming — no picks yet)

echo "▶  NFL Week 12 — posting Ravens result..."
_result "$RAVENS_ID" 27 10   # Ravens covered (Δ17 > 9.5)

echo "▶  NFL Week 12 — setting Bengals/Steelers live..."
_set_live "$BENGALS_ID"
echo "   Done"

# =============================================================================
# WORLD CUP — World Cup 2026
#
# Templates used:
#   Matchday 1 (past)    templates 1-4: France, Brazil, USA, Argentina
#   Matchday 2 (current) templates 5-8: Germany, Spain, Portugal, England
#
# Matchday 1 results:
#   France   -1.5 vs Morocco     : France wins 2-0   → France covered (Δ2 > 1.5)
#   Brazil   -1.5 vs Croatia     : Brazil wins 3-1   → Brazil covered (Δ2 > 1.5)
#   USA      -0.5 vs Mexico      : Mexico wins 2-1   → USA didn't cover, Mexico won
#   Argentina -2.5 vs S. Arabia  : Argentina wins 3-0 → Argentina covered (Δ3 > 2.5)
#
# Matchday 1 pick outcomes:
#   Alice   France WIN  Brazil WIN  USA LOSS     Argentina WIN  → 3W 1L
#   Bob     Morocco LOSS  Brazil WIN  Mexico WIN  Argentina WIN  → 3W 1L
#   Charlie France WIN  Croatia LOSS  USA LOSS   S.Arabia LOSS  → 1W 3L
#   Diana   Morocco LOSS  Brazil WIN  Mexico WIN  Argentina WIN  → 3W 1L
#
# Matchday 2:
#   Germany  -0.5 vs Japan      → FINAL  Germany 2-0 (Δ2 > 0.5, Germany covered)
#   Spain    -1.5 vs Costa Rica → LIVE   (kicked off, result pending)
#   Portugal -1.5 vs Ghana      → UPCOMING  Alice→Portugal picked
#   England  -1.5 vs Iran       → UPCOMING  no picks yet
#
# Matchday 2 pick outcomes (Germany only):
#   Alice   Germany WIN → total 4W 1L  80.0%  ← 1st (tied Diana, stable sort)
#   Bob     Japan LOSS  → total 3W 2L  60.0%  ← 3rd
#   Charlie Germany WIN → total 2W 3L  40.0%  ← 4th
#   Diana   Germany WIN → total 4W 1L  80.0%  ← 2nd
# =============================================================================

echo ""
echo "── WORLD CUP ────────────────────────────────────────────────────────────────"

# ── WC Matchday 1 (past — all final) ─────────────────────────────────────────

echo "▶  WC Matchday 1 — seeding..."
M1=$(curl -sf -X POST "$BASE/dev/seed-week" \
    -H "Content-Type: application/json" \
    -d "{\"group_id\":\"$WC_GROUP\",\"sport\":\"soccer_fifa_world_cup\",\"week_label\":\"Group Stage - Matchday 1\",\"game_count\":4}")

FRANCE_ID=$(    _game_id "$M1" "France")
BRAZIL_ID=$(    _game_id "$M1" "Brazil")
USA_ID=$(       _game_id "$M1" "United States")
ARGENTINA_ID=$( _game_id "$M1" "Argentina")

echo "▶  WC Matchday 1 — submitting picks..."

# France -1.5 vs Morocco
_pick "$ALICE_TOKEN"   "$FRANCE_ID" "$WC_GROUP" "France"
_pick "$BOB_TOKEN"     "$FRANCE_ID" "$WC_GROUP" "Morocco"
_pick "$CHARLIE_TOKEN" "$FRANCE_ID" "$WC_GROUP" "France"
_pick "$DIANA_TOKEN"   "$FRANCE_ID" "$WC_GROUP" "Morocco"

# Brazil -1.5 vs Croatia
_pick "$ALICE_TOKEN"   "$BRAZIL_ID" "$WC_GROUP" "Brazil"
_pick "$BOB_TOKEN"     "$BRAZIL_ID" "$WC_GROUP" "Brazil"
_pick "$CHARLIE_TOKEN" "$BRAZIL_ID" "$WC_GROUP" "Croatia"
_pick "$DIANA_TOKEN"   "$BRAZIL_ID" "$WC_GROUP" "Brazil"

# USA -0.5 vs Mexico
_pick "$ALICE_TOKEN"   "$USA_ID" "$WC_GROUP" "United States"
_pick "$BOB_TOKEN"     "$USA_ID" "$WC_GROUP" "Mexico"
_pick "$CHARLIE_TOKEN" "$USA_ID" "$WC_GROUP" "United States"
_pick "$DIANA_TOKEN"   "$USA_ID" "$WC_GROUP" "Mexico"

# Argentina -2.5 vs Saudi Arabia
_pick "$ALICE_TOKEN"   "$ARGENTINA_ID" "$WC_GROUP" "Argentina"
_pick "$BOB_TOKEN"     "$ARGENTINA_ID" "$WC_GROUP" "Argentina"
_pick "$CHARLIE_TOKEN" "$ARGENTINA_ID" "$WC_GROUP" "Saudi Arabia"
_pick "$DIANA_TOKEN"   "$ARGENTINA_ID" "$WC_GROUP" "Argentina"

echo "▶  WC Matchday 1 — posting results..."
_result "$FRANCE_ID"    2 0   # France covered
_result "$BRAZIL_ID"    3 1   # Brazil covered
_result "$USA_ID"       1 2   # Mexico won → USA didn't cover
_result "$ARGENTINA_ID" 3 0   # Argentina covered

# ── WC Matchday 2 (current) ───────────────────────────────────────────────────

echo "▶  WC Matchday 2 — seeding..."
M2=$(curl -sf -X POST "$BASE/dev/seed-week" \
    -H "Content-Type: application/json" \
    -d "{\"group_id\":\"$WC_GROUP\",\"sport\":\"soccer_fifa_world_cup\",\"week_label\":\"Group Stage - Matchday 2\",\"game_count\":8}")

GERMANY_ID=$(  _game_id "$M2" "Germany")
SPAIN_ID=$(    _game_id "$M2" "Spain")
PORTUGAL_ID=$( _game_id "$M2" "Portugal")
ENGLAND_ID=$(  _game_id "$M2" "England")

echo "▶  WC Matchday 2 — submitting picks..."

# Germany -0.5 vs Japan (will be finalized)
_pick "$ALICE_TOKEN"   "$GERMANY_ID" "$WC_GROUP" "Germany"
_pick "$BOB_TOKEN"     "$GERMANY_ID" "$WC_GROUP" "Japan"
_pick "$CHARLIE_TOKEN" "$GERMANY_ID" "$WC_GROUP" "Germany"
_pick "$DIANA_TOKEN"   "$GERMANY_ID" "$WC_GROUP" "Germany"

# Spain -1.5 vs Costa Rica (will become live — pick before moving kickoff)
_pick "$ALICE_TOKEN"   "$SPAIN_ID" "$WC_GROUP" "Spain"
_pick "$BOB_TOKEN"     "$SPAIN_ID" "$WC_GROUP" "Spain"
_pick "$CHARLIE_TOKEN" "$SPAIN_ID" "$WC_GROUP" "Costa Rica"
# Diana skips Spain game

# Portugal -1.5 vs Ghana (upcoming — Alice has early pick)
_pick "$ALICE_TOKEN" "$PORTUGAL_ID" "$WC_GROUP" "Portugal"

# England -1.5 vs Iran (upcoming — no picks yet)

echo "▶  WC Matchday 2 — posting Germany result..."
_result "$GERMANY_ID" 2 0   # Germany covered (Δ2 > 0.5)

echo "▶  WC Matchday 2 — setting Spain/Costa Rica live..."
_set_live "$SPAIN_ID"
echo "   Done"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Seed complete."
echo ""
echo "Test accounts (password: password123)"
echo "  alice@test.com    bob@test.com    charlie@test.com    diana@test.com"
echo ""
echo "NFL 'Sunday Crew'      join code: $NFL_CODE"
echo "  Week 11  4 games, all final"
echo "  Week 12  Ravens final | Bengals/Steelers LIVE | Lions/Packers upcoming"
echo "  Standings  Alice 85.7% · Charlie 80% · Diana 60% · Bob 40%"
echo ""
echo "WC 'World Cup 2026'    join code: $WC_CODE"
echo "  Matchday 1  4 games, all final"
echo "  Matchday 2  Germany final | Spain/Costa Rica LIVE | Portugal/England upcoming"
echo "  Standings  Alice 80% · Diana 80% · Bob 60% · Charlie 40%"
