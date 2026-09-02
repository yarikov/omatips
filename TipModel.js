.pragma library

var SCHEMA_VERSION = 1
var MINUTE_MS = 60 * 1000
var MAX_STATE_BYTES = 64 * 1024

function stateSizeAllowed(byteLength) {
  var length = Number(byteLength)
  return isFinite(length) && length >= 0 && length <= MAX_STATE_BYTES
}

function utf8ByteLength(value) {
  var text = String(value || "")
  var bytes = 0
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code < 0x80) bytes += 1
    else if (code < 0x800) bytes += 2
    else if (code >= 0xd800 && code <= 0xdbff
             && i + 1 < text.length
             && text.charCodeAt(i + 1) >= 0xdc00
             && text.charCodeAt(i + 1) <= 0xdfff) {
      bytes += 4
      i += 1
    } else bytes += 3
  }
  return bytes
}

function defaultState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    storageRevision: 0,
    nextNewIndex: 0,
    cards: Object.create(null),
    lastNotificationDate: "",
    panelSession: {
      tipId: "", answerRevealed: false, cursorTarget: "",
      preferredRating: "again", confirmationAction: "", confirmationOrigin: ""
    }
  }
}

function validPanelTarget(target) {
  return ["showAnswer", "action", "again", "hard", "good", "easy",
          "restart", "uninstall", "cancel", "confirm"].indexOf(target) !== -1
}

function validRating(rating) {
  return ["again", "hard", "good", "easy"].indexOf(rating) !== -1
}

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function normalizedCard(value) {
  if (!value || typeof value !== "object") return null
  return {
    dueAt: Math.max(0, finiteNumber(value.dueAt, 0)),
    intervalMinutes: Math.max(0, finiteNumber(value.intervalMinutes, 0)),
    ease: Math.max(1.3, finiteNumber(value.ease, 2.5)),
    repetitions: Math.max(0, Math.floor(finiteNumber(value.repetitions, 0))),
    lapses: Math.max(0, Math.floor(finiteNumber(value.lapses, 0))),
    easyStreak: Math.max(0, Math.min(3, Math.floor(finiteNumber(value.easyStreak, 0)))),
    completed: value.completed === true
  }
}

function normalizedState(value, tips, now) {
  if (!value || typeof value !== "object") return defaultState()
  if (value.schemaVersion !== SCHEMA_VERSION) return defaultState()

  var next = defaultState()
  next.storageRevision = Math.max(0, Math.floor(finiteNumber(value.storageRevision, 0)))
  next.nextNewIndex = Math.max(0, Math.floor(finiteNumber(value.nextNewIndex, 0)))
  next.nextNewIndex = Math.min(next.nextNewIndex, tips.length)
  next.lastNotificationDate = /^\d{4}-\d{2}-\d{2}$/.test(String(value.lastNotificationDate || ""))
    ? String(value.lastNotificationDate) : ""

  var known = Object.create(null)
  for (var i = 0; i < tips.length; i++) known[tips[i].id] = true
  var panel = value.panelSession
  if (panel && typeof panel === "object" && !Array.isArray(panel)) {
    var panelTipId = String(panel.tipId || "")
    var panelTarget = String(panel.cursorTarget || "")
    if (panelTipId === "" || Object.prototype.hasOwnProperty.call(known, panelTipId)) {
      next.panelSession.tipId = panelTipId
      next.panelSession.answerRevealed = panelTipId !== "" && panel.answerRevealed === true
      next.panelSession.cursorTarget = validPanelTarget(panelTarget) ? panelTarget : ""
      var preferred = String(panel.preferredRating || "")
      next.panelSession.preferredRating = validRating(preferred) ? preferred : "again"
      var confirmation = String(panel.confirmationAction || "")
      next.panelSession.confirmationAction = ["restart", "uninstall"].indexOf(confirmation) !== -1
        ? confirmation : ""
      var origin = String(panel.confirmationOrigin || "")
      next.panelSession.confirmationOrigin = validPanelTarget(origin) ? origin : ""
    }
  }
  var cards = value.cards && typeof value.cards === "object" ? value.cards : {}
  for (var id in cards) {
    if (!Object.prototype.hasOwnProperty.call(cards, id)
        || !Object.prototype.hasOwnProperty.call(known, id)) continue
    var card = normalizedCard(cards[id])
    if (card) next.cards[id] = card
  }
  return next
}

function parseState(raw, tips, now) {
  try {
    return normalizedState(JSON.parse(String(raw || "")), tips, now)
  } catch (e) {
    return defaultState()
  }
}

function validStoredState(raw) {
  var value
  try { value = JSON.parse(String(raw || "")) } catch (e) { return false }
  if (!value || typeof value !== "object" || Array.isArray(value)) return false
  if (value.schemaVersion !== SCHEMA_VERSION) return false
  if (!isFinite(Number(value.nextNewIndex)) || Number(value.nextNewIndex) < 0) return false
  if (!value.cards || typeof value.cards !== "object" || Array.isArray(value.cards)) return false
  return typeof value.lastNotificationDate === "string"
}

function dueReviews(state, tips, now) {
  var normalized = normalizedState(state, tips, now)
  var due = []
  for (var i = 0; i < normalized.nextNewIndex; i++) {
    var tip = tips[i]
    var card = normalized.cards[tip.id]
    if (card && !card.completed && card.dueAt <= now)
      due.push({ tip: tip, index: i, isNew: false, card: card, dueAt: card.dueAt })
  }
  due.sort(function(a, b) {
    if (a.dueAt !== b.dueAt) return a.dueAt - b.dueAt
    return a.index - b.index
  })

  return due
}

function nextNew(state, tips, now) {
  var normalized = normalizedState(state, tips, now)
  if (normalized.nextNewIndex >= tips.length) return null
  var index = normalized.nextNewIndex
  return { tip: tips[index], index: index, isNew: true, card: null, dueAt: now }
}

function studyQueue(state, tips, now) {
  var reviews = dueReviews(state, tips, now)
  if (reviews.length > 0) return reviews
  var unseen = nextNew(state, tips, now)
  return unseen ? [unseen] : []
}

function selectedStudyItem(queue, unseen, activeTipId) {
  var id = String(activeTipId || "")
  if (id !== "") {
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].tip && queue[i].tip.id === id) return queue[i]
    }
    if (unseen && unseen.tip && unseen.tip.id === id) return unseen
  }
  return queue.length > 0 ? queue[0] : null
}

function withPanelSession(input, tips, tipId, answerRevealed, cursorTarget,
                          preferredRating, confirmationAction, confirmationOrigin, now) {
  var state = normalizedState(input, tips, now)
  var id = String(tipId || "")
  var target = String(cursorTarget || "")
  var preferred = String(preferredRating || "")
  var confirmation = String(confirmationAction || "")
  var origin = String(confirmationOrigin || "")
  var known = id === ""
  for (var i = 0; i < tips.length; i++) {
    if (tips[i].id === id) {
      known = true
      break
    }
  }
  state.panelSession = {
    tipId: known ? id : "",
    answerRevealed: known && id !== "" && answerRevealed === true,
    cursorTarget: known && validPanelTarget(target) ? target : "",
    preferredRating: known && validRating(preferred) ? preferred : "again",
    confirmationAction: known
      && ["restart", "uninstall"].indexOf(confirmation) !== -1 ? confirmation : "",
    confirmationOrigin: known && validPanelTarget(origin) ? origin : ""
  }
  return state
}

// Kept as the combined study queue API for existing callers.
function dueQueue(state, tips, now) {
  return studyQueue(state, tips, now)
}

function currentDue(state, tips, now) {
  var queue = studyQueue(state, tips, now)
  return queue.length > 0 ? queue[0] : null
}

function studyPositionLabel(item, totalTips) {
  if (!item || item.index === undefined || item.index === null) return ""
  var position = Math.max(0, Math.floor(finiteNumber(item.index, 0))) + 1
  var total = Math.max(0, Math.floor(finiteNumber(totalTips, 0)))
  return (item.isNew ? "Tip " : "Review · Tip ") + position + " / " + total
}

function nextDueAt(state, tips, now) {
  var normalized = normalizedState(state, tips, now)
  if (normalized.nextNewIndex < tips.length) return now
  var earliest = -1
  for (var id in normalized.cards) {
    if (!Object.prototype.hasOwnProperty.call(normalized.cards, id)) continue
    if (normalized.cards[id].completed) continue
    var due = normalized.cards[id].dueAt
    if (earliest < 0 || due < earliest) earliest = due
  }
  return earliest
}

function courseCompleted(state, tips, now) {
  if (!Array.isArray(tips) || tips.length === 0) return false
  var normalized = normalizedState(state, tips, now)
  return normalized.nextNewIndex >= tips.length
    && nextDueAt(normalized, tips, now) < 0
}

function scheduledCard(previous, rating, now) {
  var old = normalizedCard(previous) || {
    dueAt: now,
    intervalMinutes: 0,
    ease: 2.5,
    repetitions: 0,
    lapses: 0,
    easyStreak: 0,
    completed: false
  }
  var interval
  var ease = old.ease
  var repetitions = old.repetitions
  var lapses = old.lapses
  var easyStreak = rating === "easy" ? old.easyStreak + 1 : 0

  if (rating === "again") {
    interval = 1
    ease = Math.max(1.3, ease - 0.2)
    repetitions = 0
    lapses += 1
  } else if (rating === "hard") {
    interval = repetitions === 0 ? 10 : Math.max(10, Math.round(old.intervalMinutes * 1.2))
    ease = Math.max(1.3, ease - 0.15)
    repetitions += 1
  } else if (rating === "good") {
    interval = repetitions === 0 ? 1440 : Math.max(1440, Math.round(old.intervalMinutes * ease))
    repetitions += 1
  } else if (rating === "easy") {
    interval = repetitions === 0 ? 5760 : Math.max(5760, Math.round(old.intervalMinutes * ease * 1.3))
    ease = Math.min(3.5, ease + 0.15)
    repetitions += 1
  } else {
    return null
  }

  return {
    dueAt: now + interval * MINUTE_MS,
    intervalMinutes: interval,
    ease: ease,
    repetitions: repetitions,
    lapses: lapses,
    easyStreak: easyStreak,
    completed: easyStreak >= 3
  }
}

function formatIntervalMinutes(value) {
  var minutes = Math.max(1, Math.round(finiteNumber(value, 1)))
  if (minutes < 60) return minutes + "m"
  var hourMinutes = 60
  var dayMinutes = 24 * hourMinutes
  var monthMinutes = 30 * dayMinutes
  var yearMinutes = 365 * dayMinutes
  var unitMinutes
  var suffix
  if (minutes < dayMinutes) {
    unitMinutes = hourMinutes
    suffix = "h"
  } else if (minutes < monthMinutes) {
    unitMinutes = dayMinutes
    suffix = "d"
  } else if (minutes < yearMinutes) {
    unitMinutes = monthMinutes
    suffix = "mo"
  } else {
    unitMinutes = yearMinutes
    suffix = "y"
  }
  var units = Math.floor(minutes / unitMinutes)
  return units + suffix + (minutes % unitMinutes > 0 ? "+" : "")
}

function ratingIntervalLabel(previous, rating, now) {
  var card = scheduledCard(previous, rating, now)
  if (!card) return ""
  return card.completed ? "Done" : formatIntervalMinutes(card.intervalMinutes)
}

function review(input, tips, tipId, rating, now) {
  var state = normalizedState(input, tips, now)
  var item = null
  for (var i = 0; i < tips.length; i++) {
    if (tips[i].id !== tipId) continue
    if (i === state.nextNewIndex) {
      item = { tip: tips[i], index: i, isNew: true, card: null, dueAt: now }
    } else if (i < state.nextNewIndex) {
      var storedCard = state.cards[tipId]
      if (storedCard && !storedCard.completed && storedCard.dueAt <= now)
        item = { tip: tips[i], index: i, isNew: false,
          card: storedCard, dueAt: storedCard.dueAt }
    }
    break
  }
  if (!item) return { state: state, reviewed: false }
  var card = scheduledCard(item.card, rating, now)
  if (!card) return { state: state, reviewed: false }

  var cards = Object.create(null)
  for (var id in state.cards) {
    if (Object.prototype.hasOwnProperty.call(state.cards, id)) cards[id] = state.cards[id]
  }
  cards[tipId] = card
  state.cards = cards
  if (item.isNew) state.nextNewIndex = Math.min(tips.length, state.nextNewIndex + 1)
  state.panelSession = defaultState().panelSession
  return { state: state, reviewed: true, card: card }
}

function localDateKey(date) {
  var year = date.getFullYear()
  var month = String(date.getMonth() + 1).padStart(2, "0")
  var day = String(date.getDate()).padStart(2, "0")
  return year + "-" + month + "-" + day
}

function studyDayKey(date) {
  if (date.getHours() >= 4) return localDateKey(date)
  return localDateKey(new Date(date.getFullYear(), date.getMonth(), date.getDate() - 1))
}

function shouldNotifyToday(state, today) {
  return String((state && state.lastNotificationDate) || "") !== String(today || "")
}

function withinNotificationHours(date) {
  var hour = date.getHours()
  return hour >= 8 && hour < 16
}

function formatWait(milliseconds) {
  var minutes = Math.max(1, Math.ceil(milliseconds / MINUTE_MS))
  if (minutes < 60) return minutes + (minutes === 1 ? " minute" : " minutes")
  var hours = Math.ceil(minutes / 60)
  if (hours < 48) return hours + (hours === 1 ? " hour" : " hours")
  var days = Math.ceil(hours / 24)
  return days + (days === 1 ? " day" : " days")
}

function validAction(action) {
  if (action === undefined || action === null) return true
  if (!action || typeof action !== "object" || typeof action.label !== "string") return false
  if (action.kind === "copy") return typeof action.text === "string" && action.text.length > 0
  if (action.kind !== "exec" || !Array.isArray(action.argv)) return false
  var argv = action.argv
  if (argv.length !== 5 || argv[0] !== "omarchy-shell" || argv[1] !== "shell" || argv[2] !== "summon" || argv[4] !== "{}") return false
  return ["omarchy.menu", "omarchy.clipboard", "omarchy.emojis"].indexOf(argv[3]) !== -1
}

function parseTips(raw) {
  var parsed
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return [] }
  if (!Array.isArray(parsed)) return []
  var seen = {}
  var valid = []
  for (var i = 0; i < parsed.length; i++) {
    var tip = parsed[i]
    if (!tip || typeof tip.id !== "string" || !tip.id || seen[tip.id]) return []
    if (typeof tip.category !== "string" || !tip.category || typeof tip.title !== "string" || !tip.title || !validAction(tip.action)) return []
    seen[tip.id] = true
    valid.push(tip)
  }
  return valid
}
