import datetime
from utils import get_run_recommendation, save_last_run_date

if __name__ == "__main__":
    # By default, let's use today's date as the run_date, but allow user input
    today = datetime.date.today()
    print("Enter run date (YYYY-MM-DD) or press enter for today's date:")
    user_input = input().strip()
    if user_input:
        run_date = datetime.date.fromisoformat(user_input)
    else:
        run_date = today

    miles, pace = get_run_recommendation(run_date)
    print(f"For {run_date.isoformat()}, you should run {miles:.2f} miles at {pace} per mile.")

    # Ask if user actually runs this date
    print("Did you run this prescribed run today? (y/n):")
    choice = input().strip().lower()
    if choice == 'y':
        save_last_run_date(run_date)
        print("Last run date updated.")
    else:
        print("Last run date not updated.")
