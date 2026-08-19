"""
APScheduler job management.

Jobs that need FCM tokens look them up from the database at fire time,
not at schedule time — tokens change when users reinstall the app.

APScheduler stores jobs in memory. For production, consider switching to
the SQLAlchemy job store so jobs survive server restarts.
"""

import logging
import uuid
from datetime import datetime, timedelta, timezone

from apscheduler.schedulers.background import BackgroundScheduler

from app.services import notifications

logger = logging.getLogger(__name__)

_SUPPORTED_SPORTS = ["americanfootball_nfl"]

scheduler = BackgroundScheduler(timezone="UTC")


def start() -> None:
    if not scheduler.running:
        scheduler.start()
        logger.info("Scheduler started.")
        _schedule_odds_refresh()
        _schedule_results_fetch()


def shutdown() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler shut down.")


# ── Public job factories ──────────────────────────────────────────────────────

_CLUSTER_WINDOW = timedelta(minutes=90)


def schedule_pick_reminders_for_week(week_id: uuid.UUID, group_id: uuid.UUID, games: list) -> None:
    """
    (Re)schedule pick-reminder notifications for every game currently on a
    week's slate, at T-120, T-60, T-30, and T-15 minutes before kickoff.

    Games whose kickoffs fall within _CLUSTER_WINDOW of each other (chained —
    each game within the window of the previous one) share a single digest
    reminder per offset instead of firing one notification per game. Without
    this, a slate with several games kicking off close together (e.g. a
    Saturday preseason batch) produces a burst of near-simultaneous
    notifications that reads as "every game" even though each one is
    correctly scoped to the slate.

    Always cancels and fully recomputes this week's jobs first, so clusters
    stay correct as games are added to or removed from the slate. FCM tokens
    and already-picked status are resolved at fire time.
    """
    from app.utils import ensure_utc

    cancel_pick_reminders_for_week(week_id)
    if not games:
        return

    ordered = sorted(games, key=lambda g: ensure_utc(g.kickoff_at))
    clusters: list[list] = []
    for game in ordered:
        if clusters and ensure_utc(game.kickoff_at) - ensure_utc(clusters[-1][-1].kickoff_at) <= _CLUSTER_WINDOW:
            clusters[-1].append(game)
        else:
            clusters.append([game])

    for cluster in clusters:
        anchor = min(ensure_utc(g.kickoff_at) for g in cluster)
        game_ids = [g.id for g in cluster]
        for minutes in [120, 60, 30, 15]:
            scheduler.add_job(
                _send_pick_reminders,
                "date",
                run_date=anchor - timedelta(minutes=minutes),
                id=f"pick_digest_{week_id}_{anchor.isoformat()}_{minutes}m",
                replace_existing=True,
                kwargs={"game_ids": game_ids, "group_id": group_id, "minutes": minutes},
            )


def cancel_pick_reminders_for_week(week_id: uuid.UUID) -> None:
    """Cancel every scheduled pick-reminder job for a week (across all clusters)."""
    prefix = f"pick_digest_{week_id}_"
    for job in scheduler.get_jobs():
        if job.id.startswith(prefix):
            scheduler.remove_job(job.id)


def schedule_slate_admin_reminder(
    week_id: uuid.UUID,
    group_id: uuid.UUID,
    first_kickoff_at: datetime,
) -> None:
    """Remind the admin to finalise the slate 3 hours before first kickoff."""
    scheduler.add_job(
        _send_slate_admin_reminder,
        "date",
        run_date=first_kickoff_at - timedelta(hours=3),
        id=f"slate_reminder_{week_id}",
        replace_existing=True,
        kwargs={"group_id": group_id},
    )


def cancel_slate_admin_reminder(week_id: uuid.UUID) -> None:
    job_id = f"slate_reminder_{week_id}"
    if scheduler.get_job(job_id):
        scheduler.remove_job(job_id)


_SPREAD_LOCK_WINDOW = timedelta(minutes=30)


def schedule_odds_refresh_for_game(
    game_id: uuid.UUID,
    sport: str,
    kickoff_at: datetime,
) -> None:
    """
    Schedule a one-time final odds refresh 30 minutes before THIS game's own
    kickoff — not just the first game of its slate. A slate can span Thursday
    through Monday; a refresh anchored only to the earliest game left the
    later games' spreads relying solely on the 24h interval job, which could
    be up to a day stale by the time they actually kick off.

    This is also the line's lock point: after this fetch, the game's spread
    is frozen (see odds.lock_game_spread) so the number everyone picked
    against and the number it's graded on can't diverge. Replaces any
    existing job for this game so fire time stays current if the game's
    kickoff changes. No-op if ODDS_API_KEY is not configured.
    """
    from app.config import settings
    if not settings.ODDS_API_KEY:
        return
    fire_at = max(kickoff_at - _SPREAD_LOCK_WINDOW, datetime.now(timezone.utc))
    scheduler.add_job(
        _refresh_and_lock_game,
        "date",
        run_date=fire_at,
        id=f"odds_refresh_game_{game_id}",
        replace_existing=True,
        kwargs={"game_id": game_id, "sport": sport},
    )
    logger.info("Final odds refresh + spread lock for game %s scheduled at %s", game_id, fire_at)


def cancel_odds_refresh_for_game(game_id: uuid.UUID) -> None:
    job_id = f"odds_refresh_game_{game_id}"
    if scheduler.get_job(job_id):
        scheduler.remove_job(job_id)


# ── Internal setup ────────────────────────────────────────────────────────────

def _schedule_odds_refresh() -> None:
    from app.config import settings
    if not settings.ODDS_API_KEY:
        logger.info("ODDS_API_KEY not set — odds refresh job not scheduled.")
        return
    scheduler.add_job(_refresh_odds_job, "date", id="odds_refresh_startup", replace_existing=True)
    scheduler.add_job(
        _refresh_odds_job,
        "interval",
        hours=24,
        id="odds_refresh_interval",
        replace_existing=True,
    )
    logger.info("Odds refresh scheduled (startup + every 24h).")


def _schedule_results_fetch() -> None:
    from app.config import settings
    if not settings.ODDS_API_KEY:
        return
    scheduler.add_job(
        _fetch_and_process_results,
        "interval",
        minutes=30,
        id="results_fetch",
        replace_existing=True,
    )
    logger.info("Results fetch scheduled (every 30 min).")


# ── Internal job functions ────────────────────────────────────────────────────

def _refresh_odds_job() -> None:
    """Refill the odds pool. Games are NEVER auto-added to any group's
    slate — the admin picks games explicitly (games.py::add_game_to_slate),
    which is also what triggers the slate-ready/game-added notification."""
    from app.services.odds import ingest_odds

    for sport in _SUPPORTED_SPORTS:
        try:
            ingest_odds(sport)
        except Exception:
            logger.exception("Odds refresh failed for sport=%s", sport)


def _refresh_sport_job(sport: str) -> None:
    from app.services.odds import ingest_odds
    try:
        ingest_odds(sport)
    except Exception:
        logger.exception("Odds refresh failed for sport=%s", sport)


def _refresh_and_lock_game(game_id: uuid.UUID, sport: str) -> None:
    """Fires 30 minutes before a game's kickoff: one last odds fetch, then
    freeze that game's spread regardless of whether the fetch found a newer
    line — see odds.lock_game_spread."""
    from app.services.odds import ingest_odds, lock_game_spread
    try:
        ingest_odds(sport)
    except Exception:
        logger.exception("Final odds refresh failed for sport=%s (game=%s)", sport, game_id)
    finally:
        lock_game_spread(game_id)


def _relevant_api_sport_key(kickoff_at: datetime) -> str:
    """Which real Odds API key a game's results actually live under, based
    on its own kickoff date — used by _fetch_and_process_results to avoid
    always querying both the regular-season+playoffs and separate preseason
    scores endpoints on every poll regardless of whether any preseason game
    is actually pending (which wastes half of every poll's Odds API credit
    budget for the ~5 months/year with no pending preseason games — i.e.
    almost the entire season)."""
    from app.services.nfl_calendar import local_date, nfl_season_start, season_year_for_date
    from app.utils import ensure_utc

    kickoff_date = local_date(ensure_utc(kickoff_at))
    season_start = nfl_season_start(season_year_for_date(kickoff_date))
    return "americanfootball_nfl_preseason" if kickoff_date < season_start else "americanfootball_nfl"


def _send_pick_reminders(
    game_ids: list[uuid.UUID],
    group_id: uuid.UUID,
    minutes: int,
) -> None:
    """
    Remind every group member as kickoff approaches — including members who
    already picked. Lines can move between when someone picks and kickoff,
    and grading uses whatever spread is on the Game row at kickoff (there's
    no spread-at-pick-time snapshot), so an already-picked member still
    benefits from a nudge to come back and re-check the line before it's
    too late to change their mind.

    game_ids is a whole kickoff cluster (see schedule_pick_reminders_for_week)
    — each member gets exactly one notification here, split into "still
    needs a pick" vs "already picked" games and worded accordingly.
    """
    from app.database import engine
    from app.models import Game, GroupMember, Pick, User
    from sqlmodel import Session, select

    with Session(engine) as session:
        games = session.exec(select(Game).where(Game.id.in_(game_ids))).all()  # type: ignore[attr-defined]
        if not games:
            return
        team_names_by_id = {g.id: f"{g.away_team} at {g.home_team}" for g in games}

        members = session.exec(
            select(User)
            .join(GroupMember, GroupMember.user_id == User.id)  # type: ignore[arg-type]
            .where(GroupMember.group_id == group_id, User.fcm_token.isnot(None))  # type: ignore[union-attr]
        ).all()

        for member in members:
            if not member.fcm_token:
                continue
            picked_ids = {
                p.game_id for p in session.exec(
                    select(Pick).where(
                        Pick.user_id == member.id,
                        Pick.group_id == group_id,
                        Pick.game_id.in_(game_ids),  # type: ignore[attr-defined]
                    )
                ).all()
            }
            unpicked_names = [team_names_by_id[gid] for gid in game_ids if gid not in picked_ids]
            picked_names = [team_names_by_id[gid] for gid in game_ids if gid in picked_ids]

            if unpicked_names:
                notifications.send_pick_digest_reminder(member.fcm_token, unpicked_names, minutes)
            if picked_names:
                notifications.send_line_check_digest_reminder(member.fcm_token, picked_names, minutes)


def _send_slate_admin_reminder(group_id: uuid.UUID) -> None:
    from app.database import engine
    from app.models import Group, User
    from sqlmodel import Session

    with Session(engine) as session:
        group = session.get(Group, group_id)
        if group is None:
            return
        admin = session.get(User, group.admin_id)
        if admin and admin.fcm_token:
            notifications.send_slate_reminder_to_admin(admin.fcm_token, group.name)


def _fetch_and_process_results() -> None:
    """
    Poll the Odds API scores endpoint for completed games, process results,
    and send FCM notifications to affected groups.
    """
    from app.database import engine
    from app.models import Game, Group, GroupMember, User, Week
    from app.services.odds import fetch_scores
    from app.services.results import process_game_result
    from app.utils import utc_now
    from sqlmodel import Session, select

    now = utc_now()

    with Session(engine) as session:
        # Only process games that are on at least one slate (have a slate_games row).
        from app.models import SlateGame
        slated_game_ids = select(SlateGame.game_id).distinct()
        pending = session.exec(
            select(Game).where(
                Game.result_posted == False,  # noqa: E712
                Game.id.in_(slated_game_ids),  # type: ignore[attr-defined]
                Game.kickoff_at <= now,
            )
        ).all()

        if not pending:
            return

        # Fetch scores only from the real Odds API key each pending game
        # actually needs (see _relevant_api_sport_key) — NOT a blind
        # expansion to every key ever mapped to 'americanfootball_nfl'.
        score_map: dict[str, tuple[int, int]] = {}
        api_sport_keys = {_relevant_api_sport_key(g.kickoff_at) for g in pending}
        for api_sport_key in api_sport_keys:
            try:
                for s in fetch_scores(api_sport_key):
                    if not s.get("completed") or not s.get("scores"):
                        continue
                    home = next((x for x in s["scores"] if x["name"] == s["home_team"]), None)
                    away = next((x for x in s["scores"] if x["name"] == s["away_team"]), None)
                    if home and away:
                        score_map[s["id"]] = (int(home["score"]), int(away["score"]))
            except Exception:
                logger.exception("Failed to fetch scores for api_sport=%s", api_sport_key)

        for game in pending:
            if not game.odds_api_id or game.odds_api_id not in score_map:
                continue
            home_score, away_score = score_map[game.odds_api_id]
            try:
                process_game_result(game.id, home_score, away_score, session)
            except ValueError:
                continue
            except Exception:
                logger.exception("Failed to process result for game %s", game.id)
                continue

            # Notify every group that has this game on a slate.
            try:
                from app.models import SlateGame
                for sg in session.exec(select(SlateGame).where(SlateGame.game_id == game.id)).all():
                    week = session.get(Week, sg.week_id)
                    if week is None:
                        continue
                    group = session.get(Group, week.group_id)
                    if group is None:
                        continue

                    members_with_tokens = session.exec(
                        select(User)
                        .join(GroupMember, GroupMember.user_id == User.id)  # type: ignore[arg-type]
                        .where(GroupMember.group_id == group.id, User.fcm_token.isnot(None))  # type: ignore[union-attr]
                    ).all()
                    tokens = [m.fcm_token for m in members_with_tokens if m.fcm_token]
                    if not tokens:
                        continue

                    notifications.send_silent_cache_invalidation(
                        tokens, "results_posted", group_id=group.id, week_id=sg.week_id
                    )

                    # Alert only when the full slate for this group's week is done.
                    slate_game_ids = [r.game_id for r in session.exec(
                        select(SlateGame).where(SlateGame.week_id == sg.week_id)
                    ).all()]
                    slate_games = session.exec(
                        select(Game).where(Game.id.in_(slate_game_ids))  # type: ignore[attr-defined]
                    ).all()
                    if all(g.result_posted for g in slate_games):
                        notifications.send_results_notification(tokens, group.name)

            except Exception:
                logger.exception("Failed to send result notifications for game %s", game.id)
