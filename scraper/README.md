# Revo gym scraper → Google Sheets

Every hour this scrapes https://revotracker.dvcklab.com/gyms. It reads the gym data the page
embeds as JSON and adds one timestamped row per gym to a Google Sheet, so the sheet
builds up history over time.

There are two ways to run it. **Use only one**, or every row will be written twice.

## Option A (recommended): Google Apps Script

`apps_script.gs` runs entirely inside Google, so you don't need a server, a service account or GitHub secrets.

1. Open the sheet → **Extensions → Apps Script**.
2. Delete the placeholder code, paste in the contents of `apps_script.gs`, and save.
3. In the function dropdown pick **`setup`** and click **Run**. Approve the permissions
   Google asks for: access to this spreadsheet, external requests and triggers.
   On the "Google hasn't verified this app" screen, click *Advanced → Go to project*,
   because it's your own script.

`setup` installs an hourly trigger and does a first scrape right away. Check
*Triggers* (clock icon) and *Executions* in the Apps Script editor to see runs.
To stop it, delete the trigger.

## Option B: GitHub Actions + service account

`scrape_gyms.py` and `.github/workflows/scrape-gyms.yml` do the same job from GitHub,
hourly at :07. The workflow is switched off until you opt in:

1. In Google Cloud Console, enable the **Google Sheets API**, create a service account and
   download a JSON key.
2. Share the sheet with the service account's email address and give it **Editor** access.
3. In the repo, go to *Settings → Secrets and variables → Actions* and add:
   - Secret `GOOGLE_SERVICE_ACCOUNT_JSON`: the whole key file
   - Secret `GOOGLE_SHEET_ID`: the ID from the sheet URL (`/spreadsheets/d/<ID>/edit`)
   - Variable `ENABLE_GITHUB_SCRAPER` = `true`
   - Optional variable `SHEET_TAB` (default `Gym Data`)

GitHub can delay scheduled runs by a few minutes. It also pauses schedules in repos that
have had no activity for 60 days, which is one more reason to prefer Option A.

Local test, without Sheets access: `pip install -r scraper/requirements.txt && python scraper/scrape_gyms.py --dry-run`

## Columns

| Column | Meaning |
|---|---|
| `scraped_at_utc` | When this run happened |
| `data_updated_utc` | When the site last refreshed the gym's count |
| `gym_name`, `gym_id`, `state`, `timezone` | Gym identity |
| `members_now` | Members currently checked in |
| `percent_full` | The site's "% full" figure |
| `est_capacity` | The site's capacity estimate (area ÷ 5 m²) |
| `squat_racks`, `members_per_rack` | Racks and members per rack |
| `area_m2` | Floor area |
| `record_id` | The site's record ID for this reading |
