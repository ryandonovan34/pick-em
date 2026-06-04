"""
Unit tests for spread rounding — the single most critical business logic function.
No database or HTTP required.
"""

import pytest
from app.services.odds import round_spread


class TestRoundSpread:
    def test_negative_whole_rounds_away_from_zero(self):
        assert round_spread(-3.0) == -3.5
        assert round_spread(-7.0) == -7.5
        assert round_spread(-10.0) == -10.5

    def test_positive_whole_rounds_away_from_zero(self):
        assert round_spread(3.0) == 3.5
        assert round_spread(7.0) == 7.5

    def test_already_half_point_unchanged(self):
        assert round_spread(-3.5) == -3.5
        assert round_spread(-7.5) == -7.5
        assert round_spread(3.5) == 3.5

    def test_large_spread(self):
        assert round_spread(-14.0) == -14.5
        assert round_spread(-14.5) == -14.5

    def test_typical_soccer_spreads(self):
        # Soccer spreads are usually small — should work the same way.
        assert round_spread(-1.0) == -1.5
        assert round_spread(-1.5) == -1.5
        assert round_spread(-0.5) == -0.5  # already half-point
