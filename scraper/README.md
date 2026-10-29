# Revo gym scraper → Google Sheets

`scrape_gyms.py` fetches https://revotracker.dvcklab.com/gyms, reads the gym data the page
embeds as JSON, and appends one row per gym to a Google Sheet. Each run adds a new
timestamped batch, so the sheet builds up history over time.

The GitHub Actions workflow `.github/workflows/scrape-gyms.yml` runs it 4 times a day
(6am, 10am, 2pm and 6pm Perth time). You can also start it manually from the **Actions** tab
(**Scrape Revo gyms to Google Sheets → Run workflow**).

## Columns

| Column | Meaning |
|---|---|
| `scraped_at_utc` | When this script ran |
| `data_updated_utc` | When the site last refreshed the gym's count |
| `gym_name`, `gym_id`, `state`, `timezone` | Gym identity |
| `members_now` | Members currently checked in |
| `percent_full` | The site's "% full" figure |
| `est_capacity` | The site's capacity estimate (area ÷ 5 m²) |
| `squat_racks`, `members_per_rack` | Racks and members per rack |
| `area_m2` | Floor area |
| `record_id` | The site's record ID for this reading |

## One-time setup

1. **Create a Google Sheet** and copy its ID from the URL:
   `https://docs.google.com/spreadsheets/d/<THIS_PART>/edit`.
2. **Create a service account** in Google Cloud Console:
   - Create or choose a project, then enable the **Google Sheets API** under *APIs & Services → Library*.
   - Go to *IAM & Admin → Service Accounts → Create service account*. It doesn't need any roles.
   - Open the account, go to *Keys → Add key → Create new key → JSON*, and download the file.
3. **Share the sheet** with the service account's email address
   (`something@project.iam.gserviceaccount.com`) and give it **Editor** access.
4. **Add the GitHub repo secrets** under *Settings → Secrets and variables → Actions*:
   - `GOOGLE_SERVICE_ACCOUNT_JSON`: paste the entire contents of the downloaded JSON key file.
   - `GOOGLE_SHEET_ID`: the sheet ID from step 1.
   - Optional repository **variable** `SHEET_TAB`: the tab to write to. The default is `Gym Data`,
     and the script creates the tab if it doesn't exist.
5. Run the workflow manually once to check it works.

To change how often it runs, edit the `cron` lines in the workflow. Times are in UTC.
GitHub can delay scheduled runs by a few minutes. It also pauses schedules in repos that
have had no activity for 60 days.

## Running locally

```bash
pip install -r scraper/requirements.txt
python scraper/scrape_gyms.py --dry-run          # print rows, no Sheets access
GOOGLE_SERVICE_ACCOUNT_JSON="$(cat key.json)" GOOGLE_SHEET_ID=... python scraper/scrape_gyms.py
```
