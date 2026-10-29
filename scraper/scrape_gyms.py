"""Scrape live gym occupancy from revotracker.dvcklab.com/gyms and append it to a Google Sheet.

The /gyms page is server-rendered by Next.js and embeds the full gym list as JSON
in its React flight payload, so we parse that instead of the visible HTML.

Environment variables:
  GOOGLE_SERVICE_ACCOUNT_JSON  Service-account key (the JSON file contents).
  GOOGLE_SHEET_ID              ID of the target spreadsheet (from its URL).
  SHEET_TAB                    Worksheet name to append to (default: "Gym Data").

Run with --dry-run to print the scraped rows without touching Google Sheets.
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

import requests

URL = "https://revotracker.dvcklab.com/gyms"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/130.0 Safari/537.36 RevoTrackerSheetSync/1.0"
)

COLUMNS = [
    "scraped_at_utc",
    "data_updated_utc",
    "gym_name",
    "gym_id",
    "state",
    "timezone",
    "members_now",
    "percent_full",
    "est_capacity",
    "squat_racks",
    "members_per_rack",
    "area_m2",
    "record_id",
]


def fetch_html():
    resp = requests.get(URL, headers={"User-Agent": USER_AGENT}, timeout=30)
    resp.raise_for_status()
    return resp.text


def extract_gyms(html):
    """Return the list of gym dicts embedded in the Next.js flight payload."""
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', html, flags=re.S)
    payload = "".join(json.loads('"' + c + '"') for c in chunks)

    decoder = json.JSONDecoder()
    for m in re.finditer(r'"data":\[', payload):
        try:
            items, _ = decoder.raw_decode(payload, m.end() - 1)
        except json.JSONDecodeError:
            continue
        if items and isinstance(items[0], dict) and "gymName" in items[0]:
            return items
    raise RuntimeError("Could not find gym data in page; the site layout may have changed")


def to_rows(gyms, scraped_at):
    rows = []
    for g in gyms:
        pct = g.get("percentage")
        count = g.get("count")
        area = g.get("areaSize")
        # The site estimates capacity as one member per 5 m² of floor space.
        capacity = round(area / 5) if area else ""
        racks = g.get("squatRacks")
        per_rack = round(count / racks, 1) if count is not None and racks else ""
        rows.append([
            scraped_at,
            g.get("created", ""),
            g.get("gymName", ""),
            g.get("gymId", ""),
            g.get("state", ""),
            g.get("timezone", ""),
            count if count is not None else "",
            round(pct, 1) if pct is not None else "",
            capacity,
            racks if racks is not None else "",
            per_rack,
            area if area is not None else "",
            g.get("id", ""),
        ])
    return rows


def append_to_sheet(rows):
    import gspread

    creds = json.loads(os.environ["GOOGLE_SERVICE_ACCOUNT_JSON"])
    client = gspread.service_account_from_dict(creds)
    sheet = client.open_by_key(os.environ["GOOGLE_SHEET_ID"])
    tab = os.environ.get("SHEET_TAB") or "Gym Data"

    try:
        ws = sheet.worksheet(tab)
    except gspread.WorksheetNotFound:
        ws = sheet.add_worksheet(title=tab, rows=1000, cols=len(COLUMNS))

    if ws.row_values(1) != COLUMNS:
        ws.update(range_name="A1", values=[COLUMNS])
        ws.freeze(rows=1)

    ws.append_rows(rows, value_input_option="USER_ENTERED")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="print rows instead of writing to Sheets")
    args = parser.parse_args()

    scraped_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    gyms = extract_gyms(fetch_html())
    rows = to_rows(gyms, scraped_at)

    if args.dry_run:
        print("\t".join(COLUMNS))
        for r in rows:
            print("\t".join(str(v) for v in r))
    else:
        append_to_sheet(rows)

    print(f"Scraped {len(rows)} gyms at {scraped_at} UTC", file=sys.stderr)


if __name__ == "__main__":
    main()
