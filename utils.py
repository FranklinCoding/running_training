from typing import Tuple
import datetime
import os
from config import (
    LAST_RUN_FILE,
    INITIAL_DATE,
    INITIAL_PACE,
    PACE_REDUCTION_START,
    PACE_REDUCTION_INTERVAL_DAYS,
    PACE_REDUCTION_SECONDS,
    START_YEAR,
    START_MONTH,
    INITIAL_MILES,
    SKIPPED_DAYS_INCREMENT
)

def load_last_run_date():
    if not os.path.exists(LAST_RUN_FILE):
        with open(LAST_RUN_FILE, "w") as f:
            f.write(INITIAL_DATE.isoformat())
        return INITIAL_DATE
    else:
        with open(LAST_RUN_FILE, "r") as f:
            date_str = f.read().strip()
            if not date_str:
                # If empty, write INITIAL_DATE
                with open(LAST_RUN_FILE, "w") as fw:
                    fw.write(INITIAL_DATE.isoformat())
                return INITIAL_DATE
            return datetime.date.fromisoformat(date_str)


def save_last_run_date(run_date: datetime.date):
    """Save the last run date to a file."""
    with open(LAST_RUN_FILE, "w") as f:
        f.write(run_date.isoformat())


def calculate_default_miles(run_date: datetime.date) -> float:
    """
    Calculate the base default miles for the given run_date.
    We start at 2 miles in December 2024.
    Each month starting January 2025, add 1 mile.
    """
    # months_passed = (run_date.year - 2024)*12 + (run_date.month - 12)
    months_passed = (run_date.year - START_YEAR) * 12 + (run_date.month - START_MONTH)
    if months_passed < 0:
        # Before our start date scenario
        return INITIAL_MILES

    # Default miles = initial (2) + months_passed
    return INITIAL_MILES + months_passed


def calculate_miles_with_skipped_days(base_miles: float, last_run_date: datetime.date, run_date: datetime.date) -> float:
    """
    For every day not run since last run date, add 0.5 miles.
    If last run = Dec 10 and run_date = Dec 13, difference is 3 days.
    Missed days = 3 - 1 = 2, so add 2 * 0.5 = 1 mile to base.
    """
    day_diff = (run_date - last_run_date).days
    if day_diff <= 1:
        # No missed days
        return base_miles
    missed_days = day_diff - 1
    increment = SKIPPED_DAYS_INCREMENT * missed_days
    return base_miles + increment


def calculate_pace(run_date: datetime.date) -> int:
    """
    Calculate the pace in seconds based on 2-week intervals since Dec 22, 2024.
    Before Dec 22, 2024: pace = INITIAL_PACE
    After Dec 22, every 14 days reduce pace by 15s.
    """
    if run_date < PACE_REDUCTION_START:
        return INITIAL_PACE
    diff_days = (run_date - PACE_REDUCTION_START).days
    intervals = diff_days // PACE_REDUCTION_INTERVAL_DAYS
    reduced_pace = INITIAL_PACE - (intervals * PACE_REDUCTION_SECONDS)
    return max(reduced_pace, 0)


def format_pace(seconds: int) -> str:
    """Convert seconds to a mm:ss format."""
    minutes = seconds // 60
    secs = seconds % 60
    return f"{minutes}m {secs:02d}s"


def get_run_recommendation(run_date: datetime.date) -> Tuple[float, str]:
    """
    Given a run_date, compute recommended miles and pace.
    """
    last_run_date = load_last_run_date()
    base_miles = calculate_default_miles(run_date)
    recommended_miles = calculate_miles_with_skipped_days(base_miles, last_run_date, run_date)
    pace_seconds = calculate_pace(run_date)
    pace_str = format_pace(pace_seconds)
    return recommended_miles, pace_str
