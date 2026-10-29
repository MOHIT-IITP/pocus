// Pocus — pure date, duration, trend and heatmap helpers.
//
// Kept free of QML imports so the same code can be exercised with node while
// iterating on the maths. Entries are per-day objects:
//
//   { p: productive seconds, o: off seconds }
//
// All dates are local calendar dates; comparisons use UTC day numbers so DST
// changes cannot create a phantom or missing day.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var MONTHS_LONG = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var WEEKDAY_LABELS = ["M", "T", "W", "T", "F", "S", "S"]

// A day counts toward the streak once it has at least 25 productive minutes.
var STREAK_THRESHOLD_SECONDS = 25 * 60

function pad2(value) {
  return value < 10 ? "0" + value : String(value)
}

function dateKey(date) {
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function parseKey(key) {
  var match = String(key || "").match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!match) return new Date(NaN)
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
}

function dayNumber(key) {
  var date = parseKey(key)
  if (isNaN(date.getTime())) return NaN
  return Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000)
}

function addDays(date, days) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

// Monday = 0 … Sunday = 6.
function mondayIndex(date) {
  return (date.getDay() + 6) % 7
}

function isoWeek(date) {
  var target = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  var day = (target.getDay() + 6) % 7
  target.setDate(target.getDate() - day + 3)

  var firstThursday = new Date(target.getFullYear(), 0, 4)
  var firstDay = (firstThursday.getDay() + 6) % 7
  firstThursday.setDate(firstThursday.getDate() - firstDay + 3)

  return 1 + Math.round((target.getTime() - firstThursday.getTime()) / (7 * 86400000))
}

function normalizeEntry(entry) {
  if (!entry || typeof entry !== "object") return { p: 0, o: 0 }
  var productive = Number(entry.p)
  var off = Number(entry.o)
  if (!isFinite(productive) || productive < 0) productive = 0
  if (!isFinite(off) || off < 0) off = 0
  return { p: Math.round(productive), o: Math.round(off) }
}

function addEntry(entry, productive, off) {
  var base = normalizeEntry(entry)
  var nextP = base.p + Math.max(0, Number(productive) || 0)
  var nextO = base.o + Math.max(0, Number(off) || 0)
  return { p: Math.round(nextP), o: Math.round(nextO) }
}

// Today's live counters win over a stale copy in the history file.
function mergedDay(history, todayKey, todayProductive, todayOff, key) {
  if (String(key) === String(todayKey)) {
    return normalizeEntry({ p: todayProductive, o: todayOff })
  }
  var entry = history ? history[key] : null
  return normalizeEntry(entry)
}

function historyWithToday(history, todayKey, todayProductive, todayOff) {
  var copy = {}
  if (history && typeof history === "object") {
    for (var key in history) copy[key] = normalizeEntry(history[key])
  }
  copy[todayKey] = normalizeEntry({ p: todayProductive, o: todayOff })
  return copy
}

function productiveSecondsFor(history, todayKey, todayProductive, todayOff, key) {
  return mergedDay(history, todayKey, todayProductive, todayOff, key).p
}

function offSecondsFor(history, todayKey, todayProductive, todayOff, key) {
  return mergedDay(history, todayKey, todayProductive, todayOff, key).o
}

function hasFocus(history, todayKey, todayProductive, todayOff, key) {
  return productiveSecondsFor(history, todayKey, todayProductive, todayOff, key) >= STREAK_THRESHOLD_SECONDS
}

// A day counts toward the streak once it has at least 25 productive minutes.
// Today is allowed to be below the threshold without breaking the streak (the
// day is not over yet), so we start counting from yesterday in that case.
function currentStreak(history, todayKey, todayProductive, todayOff) {
  var cursor = parseKey(todayKey)
  if (isNaN(cursor.getTime())) return 0

  if (!hasFocus(history, todayKey, todayProductive, todayOff, dateKey(cursor))) {
    cursor = addDays(cursor, -1)
  }

  var count = 0
  while (hasFocus(history, todayKey, todayProductive, todayOff, dateKey(cursor))) {
    count += 1
    cursor = addDays(cursor, -1)
  }
  return count
}

// Best run of qualifying days across every day on record, today included.
function bestStreak(history, todayKey, todayProductive, todayOff) {
  var source = historyWithToday(history, todayKey, todayProductive, todayOff)
  var keys = Object.keys(source).filter(function(key) {
    return normalizeEntry(source[key]).p >= STREAK_THRESHOLD_SECONDS
  })
  keys.sort()

  var best = 0
  var run = 0
  var previous = null
  for (var i = 0; i < keys.length; i++) {
    var current = dayNumber(keys[i])
    if (!isFinite(current)) continue
    if (previous !== null && current === previous + 1) run += 1
    else run = 1
    if (run > best) best = run
    previous = current
  }
  return best
}

// Heatmap intensity from a day's productive minutes. Half an hour is the
// first shade, two hours is a full cell.
function levelFor(minutes) {
  var value = Number(minutes)
  if (!isFinite(value) || value <= 0) return 0
  if (value < 30) return 1
  if (value < 60) return 2
  if (value < 120) return 3
  return 4
}

function formatDuration(seconds) {
  var value = Math.max(0, Number(seconds) || 0)
  if (value < 1) return "0m"
  if (value < 60) return Math.round(value) + "s"

  var totalMinutes = Math.floor(value / 60)
  if (totalMinutes < 60) return totalMinutes + "m"

  var hours = Math.floor(totalMinutes / 60)
  var rest = totalMinutes % 60
  return rest > 0 ? hours + "h " + rest + "m" : hours + "h"
}

function formatHMS(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var secs = total % 60
  return pad2(hours) + ":" + pad2(minutes) + ":" + pad2(secs)
}

function formatDay(key) {
  var date = parseKey(key)
  if (isNaN(date.getTime())) return ""
  return WEEKDAYS[date.getDay()] + " " + date.getDate() + " " + MONTHS[date.getMonth()]
}

// Last `count` days ending today. Values are in minutes so the chart can draw
// fractional days; the footer formats the underlying seconds.
function buildTrend(history, todayKey, todayProductive, todayOff, count) {
  var days = Math.max(1, Math.floor(Number(count) || 14))
  var today = parseKey(todayKey)
  if (isNaN(today.getTime())) today = new Date()

  var out = []
  var maxP = 0
  var maxO = 0
  var totalP = 0
  var totalO = 0

  for (var i = days - 1; i >= 0; i--) {
    var date = addDays(today, -i)
    var key = dateKey(date)
    var entry = mergedDay(history, todayKey, todayProductive, todayOff, key)
    var p = entry.p / 60
    var o = entry.o / 60
    if (p > maxP) maxP = p
    if (o > maxO) maxO = o
    totalP += p
    totalO += o
    out.push({
      key: key,
      label: String(date.getDate()),
      weekday: WEEKDAYS[date.getDay()].charAt(0),
      p: p,
      o: o,
      productiveSeconds: entry.p,
      offSeconds: entry.o,
      isToday: key === todayKey
    })
  }

  return {
    days: out,
    maxProductive: maxP,
    maxOff: maxO,
    averageProductive: totalP / days,
    averageOff: totalO / days
  }
}

function series(days, key) {
  var out = []
  for (var i = 0; i < days.length; i++) out.push(Number(days[i][key]) || 0)
  return out
}

// Build a Monday-to-Sunday grid of `weekCount` columns ending with the current
// week. Returns pure data so QML can focus on layout.
function buildHeatmap(history, todayKey, todayProductive, todayOff, weekCount) {
  var columns = Math.max(1, Math.floor(Number(weekCount) || 52))
  var today = parseKey(todayKey)
  if (isNaN(today.getTime())) today = new Date()
  var todayNumber = dayNumber(todayKey)

  var end = addDays(today, 6 - mondayIndex(today))
  var start = addDays(end, -(columns * 7 - 1))

  var weeks = []
  var monthLabels = []
  var totalProductive = 0
  var totalOff = 0
  var activeDays = 0

  for (var w = 0; w < columns; w++) {
    var monday = addDays(start, w * 7)
    var previousMonday = w > 0 ? addDays(start, (w - 1) * 7) : null
    var label = ""

    if (w === 0 || (previousMonday && monday.getMonth() !== previousMonday.getMonth())) {
      label = MONTHS[monday.getMonth()]
      monthLabels.push({ column: w, text: label })
    }

    var days = []
    for (var r = 0; r < 7; r++) {
      var date = addDays(start, w * 7 + r)
      var key = dateKey(date)
      var future = dayNumber(key) > todayNumber
      var entry = mergedDay(history, todayKey, todayProductive, todayOff, key)
      var minutes = entry.p / 60

      if (!future) {
        totalProductive += entry.p
        totalOff += entry.o
        if (entry.p > 0) activeDays += 1
      }

      days.push({
        key: key,
        productiveSeconds: entry.p,
        offSeconds: entry.o,
        minutes: minutes,
        future: future,
        level: future ? 0 : levelFor(minutes),
        row: r
      })
    }

    weeks.push({
      days: days,
      label: label,
      mondayKey: dateKey(monday),
      weekNumber: isoWeek(monday)
    })
  }

  var currentWeek = weeks[weeks.length - 1]
  var weekProductive = 0
  var weekOff = 0
  for (var i = 0; i < currentWeek.days.length; i++) {
    if (!currentWeek.days[i].future) {
      weekProductive += currentWeek.days[i].productiveSeconds
      weekOff += currentWeek.days[i].offSeconds
    }
  }

  return {
    weeks: weeks,
    monthLabels: monthLabels,
    weekProductive: weekProductive,
    weekOff: weekOff,
    weekNumber: currentWeek.weekNumber,
    totalProductive: totalProductive,
    totalOff: totalOff,
    activeDays: activeDays,
    streak: currentStreak(history, todayKey, todayProductive, todayOff),
    bestStreak: bestStreak(history, todayKey, todayProductive, todayOff)
  }
}

// Strongest productive day on record, today included.
function bestDay(history, todayKey, todayProductive, todayOff) {
  var source = historyWithToday(history, todayKey, todayProductive, todayOff)
  var bestKey = ""
  var best = 0

  for (var key in source) {
    var entry = normalizeEntry(source[key])
    if (entry.p > best) {
      best = entry.p
      bestKey = key
    }
  }

  return { key: bestKey, seconds: best }
}

// Keep roughly a year of history; enough for the 52-week heatmap plus context.
function prune(history, todayKey, keepDays) {
  var keep = Math.max(60, Math.floor(Number(keepDays) || 400))
  var cutoff = dayNumber(todayKey) - keep
  var out = {}

  if (!history || typeof history !== "object") return out

  for (var key in history) {
    var day = dayNumber(key)
    if (!isFinite(day) || day < cutoff) continue
    out[key] = normalizeEntry(history[key])
  }

  return out
}
