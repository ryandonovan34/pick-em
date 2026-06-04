"""
Unit tests for result processing logic.
Tests cover all pick outcome permutations: win, loss, superdog_win.
"""

import uuid
from datetime import datetime, timezone

import pytest
from sqlmodel import Session, SQLModel, create_engine, select

from app.models import Game, Group, GroupMember, Pick, Standing, User
from app.auth.password import hash_password
from app.services.results import process_game_result, _did_favorite_cover, _did_underdog_win_outright


# ── In-memory DB for unit tests ───────────────────────────────────────────────

@pytest.fixture(name="mem_session")
def mem_session_fixture():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    SQLModel.metadata.create_all(engine)
    from sqlmodel import Session as _Session
    with _Session(engine) as session:
        yield session
    SQLModel.metadata.drop_all(engine)


def _make_game(home: str, away: str, spread: float, favorite: str, session: Session) -> Game:
    game = Game(
        sport="americanfootball_nfl",
        home_team=home,
        away_team=away,
        spread=spread,
        favorite_team=favorite,
        kickoff_at=datetime.now(timezone.utc),
    )
    session.add(game)
    session.flush()
    return game


def _make_user(name: str, session: Session) -> User:
    user = User(email=f"{name}@test.com", display_name=name, hashed_pw=hash_password("pass"))
    session.add(user)
    session.flush()
    return user


def _make_group_with_member(user: User, session: Session) -> Group:
    group = Group(
        name="Test", admin_id=user.id, join_code=str(uuid.uuid4())[:6].upper(),
        sport="americanfootball_nfl", mode="season", season_year=2025,
    )
    session.add(group)
    session.flush()
    session.add(GroupMember(group_id=group.id, user_id=user.id))
    session.flush()
    return group


def _make_pick(user: User, game: Game, group: Group, team: str, is_superdog: bool, session: Session) -> Pick:
    pick = Pick(user_id=user.id, game_id=game.id, group_id=group.id,
                picked_team=team, is_superdog=is_superdog)
    session.add(pick)
    session.flush()
    return pick


# ── Cover calculation helpers ─────────────────────────────────────────────────

class TestCoverCalculation:
    def test_home_favorite_covers(self):
        game = Game(home_team="Chiefs", away_team="Raiders", spread=-7.5,
                    favorite_team="Chiefs", sport="nfl",
                    kickoff_at=datetime.now(timezone.utc))
        assert _did_favorite_cover(game, 27, 17) is True   # Chiefs win by 10 > 7.5
        assert _did_favorite_cover(game, 24, 17) is False  # Chiefs win by 7 < 7.5

    def test_away_favorite_covers(self):
        game = Game(home_team="Raiders", away_team="Chiefs", spread=7.5,
                    favorite_team="Chiefs", sport="nfl",
                    kickoff_at=datetime.now(timezone.utc))
        # Chiefs (away) need to win by more than 7.5
        assert _did_favorite_cover(game, 17, 27) is True   # Chiefs win by 10
        assert _did_favorite_cover(game, 20, 24) is False  # Chiefs win by 4

    def test_underdog_wins_outright_home(self):
        game = Game(home_team="Raiders", away_team="Chiefs", spread=-7.5,
                    favorite_team="Chiefs", sport="nfl",
                    kickoff_at=datetime.now(timezone.utc))
        # Underdog is Raiders (home)
        assert _did_underdog_win_outright(game, 24, 17) is True   # Raiders win
        assert _did_underdog_win_outright(game, 17, 24) is False  # Chiefs win


# ── Full result processing ────────────────────────────────────────────────────

class TestProcessGameResult:
    def test_favorite_cover_gives_favorite_picker_win(self, mem_session: Session):
        user = _make_user("Alice", mem_session)
        group = _make_group_with_member(user, mem_session)
        game = _make_game("Chiefs", "Raiders", -7.5, "Chiefs", mem_session)
        pick = _make_pick(user, game, group, "Chiefs", False, mem_session)
        mem_session.commit()

        process_game_result(game.id, 27, 17, mem_session)

        mem_session.refresh(pick)
        assert pick.result == "win"

    def test_favorite_cover_gives_underdog_picker_loss(self, mem_session: Session):
        user = _make_user("Bob", mem_session)
        group = _make_group_with_member(user, mem_session)
        game = _make_game("Chiefs", "Raiders", -7.5, "Chiefs", mem_session)
        pick = _make_pick(user, game, group, "Raiders", False, mem_session)
        mem_session.commit()

        process_game_result(game.id, 27, 17, mem_session)

        mem_session.refresh(pick)
        assert pick.result == "loss"

    def test_underdog_cover_gives_underdog_picker_win(self, mem_session: Session):
        user = _make_user("Alice", mem_session)
        group = _make_group_with_member(user, mem_session)
        game = _make_game("Chiefs", "Raiders", -7.5, "Chiefs", mem_session)
        pick = _make_pick(user, game, group, "Raiders", False, mem_session)
        mem_session.commit()

        # Chiefs win by only 3 — Raiders covered the -7.5
        process_game_result(game.id, 20, 17, mem_session)

        mem_session.refresh(pick)
        assert pick.result == "win"

    def test_superdog_win_when_underdog_wins_outright(self, mem_session: Session):
        user = _make_user("Alice", mem_session)
        group = _make_group_with_member(user, mem_session)
        game = _make_game("Chiefs", "Raiders", -7.5, "Chiefs", mem_session)
        pick = _make_pick(user, game, group, "Raiders", True, mem_session)
        mem_session.commit()

        # Raiders win outright — superdog scores 3 wins
        process_game_result(game.id, 17, 24, mem_session)

        mem_session.refresh(pick)
        assert pick.result == "superdog_win"

    def test_superdog_loss_when_underdog_loses(self, mem_session: Session):
        user = _make_user("Alice", mem_session)
        group = _make_group_with_member(user, mem_session)
        game = _make_game("Chiefs", "Raiders", -7.5, "Chiefs", mem_session)
        pick = _make_pick(user, game, group, "Raiders", True, mem_session)
        mem_session.commit()

        # Chiefs win — superdog pick loses (counts as 1 loss)
        process_game_result(game.id, 27, 17, mem_session)

        mem_session.refresh(pick)
        assert pick.result == "loss"

    def test_standings_updated_after_result(self, mem_session: Session):
        user = _make_user("Alice", mem_session)
        group = _make_group_with_member(user, mem_session)
        game = _make_game("Chiefs", "Raiders", -7.5, "Chiefs", mem_session)
        _make_pick(user, game, group, "Chiefs", False, mem_session)
        mem_session.commit()

        process_game_result(game.id, 27, 17, mem_session)

        standing = mem_session.exec(
            select(Standing).where(
                Standing.user_id == user.id, Standing.group_id == group.id
            )
        ).first()
        assert standing is not None
        assert standing.wins == 1
        assert standing.losses == 0

    def test_cannot_post_result_twice(self, mem_session: Session):
        user = _make_user("Alice", mem_session)
        group = _make_group_with_member(user, mem_session)
        game = _make_game("Chiefs", "Raiders", -7.5, "Chiefs", mem_session)
        mem_session.commit()

        process_game_result(game.id, 27, 17, mem_session)
        with pytest.raises(ValueError, match="Results already posted"):
            process_game_result(game.id, 27, 17, mem_session)
