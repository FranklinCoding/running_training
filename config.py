import datetime

# Initial conditions
INITIAL_DATE = datetime.date(2024, 12, 10)
INITIAL_MILES = 2.0
INITIAL_PACE = (10 * 60) + 30  # 10 min 30 sec in total seconds

# Pace reduction schedule:
# Every 2 weeks starting from Dec 22, 2024
PACE_REDUCTION_START = datetime.date(2024, 12, 22)
PACE_REDUCTION_INTERVAL_DAYS = 14
PACE_REDUCTION_SECONDS = 15  # seconds reduced every 2-week interval

# Monthly mileage increase:
# Starting January 2025, add 1 mile to the default per month.
START_YEAR = 2024
START_MONTH = 12  # December 2024 is our start month
START_MILES = INITIAL_MILES  # The base miles for Dec 2024

# Skipped days mileage increment:
# 0.5 miles per day not run since last run date
SKIPPED_DAYS_INCREMENT = 0.5

# File to store last run date
LAST_RUN_FILE = "last_run_date.txt"
