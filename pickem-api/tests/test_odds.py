"""
Unit tests for odds.py's sport-key mapping and ingest normalization.

The Odds API splits NFL into separate endpoints per phase of the season
('americanfootball_nfl' vs 'americanfootball_nfl_preseason'), but the app's
internal/group-facing sport key stays unified as 'americanfootball_nfl' so a
group's sport filter, include_preseason/include_playoffs flags, etc. all
work across the whole season without caring which real endpoint a game's
odds came from.
"""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

from sqlmodel import Session, SQLModel, create_engine, select

from app.config import settings
from app.models import Game
from app.services.odds import ingest_odds, odds_api_sport_keys


def _raw_game(game_id: str, home: str, away: str, spread: float, commence: str) -> dict:
    return {
        "id": game_id,
        "home_team": home,
        "away_team": away,
        "commence_time": commence,
        "bookmakers": [{
            "markets": [{
                "key": "spreads",
                "outcomes": [
                    {"name": home, "point": spread},
                    {"name": away, "point": -spread},
                ],
            }],
        }],
    }


class TestOddsApiSportKeys:
    def test_nfl_expands_to_regular_and_preseason(self):
        assert odds_api_sport_keys("americanfootball_nfl") == [
            "americanfootball_nfl", "americanfootball_nfl_preseason",
        ]

    def test_unmapped_sport_falls_back_to_itself(self):
        assert odds_api_sport_keys("basketball_nba") == ["basketball_nba"]


class TestIngestOddsNormalizesSport:
    def test_preseason_and_regular_season_games_both_stored_under_internal_sport_key(self):
        engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
        SQLModel.metadata.create_all(engine)

        def fake_get(url, params=None, timeout=None):
            resp = MagicMock()
            resp.raise_for_status = MagicMock()
            if "preseason" in url:
                resp.json.return_value = [_raw_game(
                    "pre-1", "Kansas City Chiefs", "Detroit Lions", -1.5,
                    "2026-08-07T00:15:00Z",
                )]
            else:
                resp.json.return_value = [_raw_game(
                    "reg-1", "Buffalo Bills", "Miami Dolphins", -6.5,
                    "2026-09-10T17:00:00Z",
                )]
            return resp

        with patch("app.services.odds.engine", engine), \
             patch.object(settings, "ODDS_API_KEY", "test-key"), \
             patch("app.services.odds.httpx.Client") as mock_client_cls:
            mock_client = MagicMock()
            mock_client.get.side_effect = fake_get
            mock_client_cls.return_value.__enter__.return_value = mock_client

            count = ingest_odds("americanfootball_nfl")

        assert count == 2
        with Session(engine) as session:
            games = session.exec(select(Game)).all()
            sports = {g.sport for g in games}
            odds_ids = {g.odds_api_id for g in games}

        # Both the preseason and regular-season game are stored under the
        # SAME internal sport key, regardless of which real API endpoint
        # they came from.
        assert sports == {"americanfootball_nfl"}
        assert odds_ids == {"pre-1", "reg-1"}
