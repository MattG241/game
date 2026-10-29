/**
 * Revo gym scraper for Google Apps Script.
 *
 * Paste this into the sheet's Extensions → Apps Script editor, then run `setup` once.
 * It appends one row per gym from https://revotracker.dvcklab.com/gyms every hour.
 * Runs entirely inside Google; no servers, keys or GitHub secrets needed.
 */

var URL = 'https://revotracker.dvcklab.com/gyms';
var COLUMNS = [
  'scraped_at_utc', 'data_updated_utc', 'gym_name', 'gym_id', 'state', 'timezone',
  'members_now', 'percent_full', 'est_capacity', 'squat_racks', 'members_per_rack',
  'area_m2', 'record_id'
];

/** Run once: installs the hourly trigger and does a first scrape. */
function setup() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'scrapeGyms') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('scrapeGyms').timeBased().everyHours(1).create();
  scrapeGyms();
}

function scrapeGyms() {
  var resp = UrlFetchApp.fetch(URL, { muteHttpExceptions: true });
  if (resp.getResponseCode() !== 200) {
    throw new Error('Fetch failed: HTTP ' + resp.getResponseCode());
  }
  var gyms = extractGyms(resp.getContentText());
  var scrapedAt = Utilities.formatDate(new Date(), 'UTC', 'yyyy-MM-dd HH:mm:ss');
  var rows = toRows(gyms, scrapedAt);

  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];
  var header = sheet.getRange(1, 1, 1, COLUMNS.length).getValues()[0];
  if (header.join(',') !== COLUMNS.join(',')) {
    sheet.getRange(1, 1, 1, COLUMNS.length).setValues([COLUMNS]);
    sheet.setFrozenRows(1);
  }
  sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, COLUMNS.length).setValues(rows);
}

/** The page is Next.js; the gym list is embedded as JSON in its flight payload. */
function extractGyms(html) {
  var re = /self\.__next_f\.push\(\[1,"([\s\S]*?)"\]\)/g;
  var payload = '';
  var m;
  while ((m = re.exec(html)) !== null) payload += JSON.parse('"' + m[1] + '"');

  var marker = '"data":[';
  for (var i = payload.indexOf(marker); i !== -1; i = payload.indexOf(marker, i + 1)) {
    var start = i + marker.length - 1;
    var end = matchBracket(payload, start);
    if (end === -1) continue;
    try {
      var items = JSON.parse(payload.substring(start, end + 1));
      if (items.length && items[0] && items[0].gymName !== undefined) return items;
    } catch (e) { /* not the array we want */ }
  }
  throw new Error('Could not find gym data in page; the site layout may have changed');
}

/** Index of the bracket closing the one at `start`, skipping over JSON strings. */
function matchBracket(s, start) {
  var depth = 0, inStr = false;
  for (var i = start; i < s.length; i++) {
    var c = s[i];
    if (inStr) {
      if (c === '\\') i++;
      else if (c === '"') inStr = false;
    } else if (c === '"') inStr = true;
    else if (c === '[' || c === '{') depth++;
    else if (c === ']' || c === '}') {
      if (--depth === 0) return i;
    }
  }
  return -1;
}

function toRows(gyms, scrapedAt) {
  return gyms.map(function (g) {
    var count = g.count, pct = g.percentage, racks = g.squatRacks, area = g.areaSize;
    return [
      scrapedAt,
      g.created || '',
      g.gymName || '',
      g.gymId || '',
      g.state || '',
      g.timezone || '',
      count != null ? count : '',
      pct != null ? Math.round(pct * 10) / 10 : '',
      // The site estimates capacity as one member per 5 m² of floor space.
      area ? Math.round(area / 5) : '',
      racks != null ? racks : '',
      count != null && racks ? Math.round(count / racks * 10) / 10 : '',
      area != null ? area : '',
      g.id || ''
    ];
  });
}
