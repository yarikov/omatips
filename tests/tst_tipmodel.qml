import QtQuick
import QtTest
import "../TipModel.js" as TipModel

TestCase {
  name: "TipModel"

  readonly property var tips: [
    { id: "one", category: "Test", title: "One", description: "First" },
    { id: "two", category: "Test", title: "Two", description: "Second" },
    { id: "three", category: "Test", title: "Three", description: "Third" }
  ]

  function test_newCourseStartsWithFirstTipImmediately() {
    var item = TipModel.currentDue(TipModel.defaultState(), tips, 1000)
    compare(item.tip.id, "one")
    verify(item.isNew)
    compare(TipModel.dueReviews(TipModel.defaultState(), tips, 1000).length, 0)
  }

  function test_goodIntroducesNextTipWithoutWaitingForADay() {
    var result = TipModel.review(TipModel.defaultState(), tips, "one", "good", 1000)
    verify(result.reviewed)
    compare(result.state.nextNewIndex, 1)
    compare(result.card.intervalMinutes, 1440)

    var next = TipModel.currentDue(result.state, tips, 1001)
    compare(next.tip.id, "two")
    verify(next.isNew)
  }

  function test_dueReviewsComeBeforeNewMaterial() {
    var state = TipModel.review(TipModel.defaultState(), tips, "one", "again", 1000).state
    var before = TipModel.currentDue(state, tips, 1000 + 30000)
    compare(before.tip.id, "two")
    verify(before.isNew)

    var after = TipModel.currentDue(state, tips, 1000 + 60000)
    compare(after.tip.id, "one")
    verify(!after.isNew)
    compare(TipModel.dueReviews(state, tips, 1000 + 60000).length, 1)
  }

  function test_intervalsMatchRatings() {
    compare(TipModel.scheduledCard(null, "again", 0).intervalMinutes, 1)
    compare(TipModel.scheduledCard(null, "hard", 0).intervalMinutes, 10)
    compare(TipModel.scheduledCard(null, "good", 0).intervalMinutes, 1440)
    compare(TipModel.scheduledCard(null, "easy", 0).intervalMinutes, 5760)
  }

  function test_initialRatingLabelsMatchScheduledIntervals() {
    compare(TipModel.ratingIntervalLabel(null, "again", 0), "1m")
    compare(TipModel.ratingIntervalLabel(null, "hard", 0), "10m")
    compare(TipModel.ratingIntervalLabel(null, "good", 0), "1d")
    compare(TipModel.ratingIntervalLabel(null, "easy", 0), "4d")
  }

  function test_reviewRatingLabelsPreviewGrowingIntervals() {
    var previous = { dueAt: 0, intervalMinutes: 1440, ease: 2.5, repetitions: 1, lapses: 0 }
    compare(TipModel.ratingIntervalLabel(previous, "again", 1000), "1m")
    compare(TipModel.ratingIntervalLabel(previous, "hard", 1000), "1d+")
    compare(TipModel.ratingIntervalLabel(previous, "good", 1000), "2d+")
    compare(TipModel.ratingIntervalLabel(previous, "easy", 1000), "4d")
  }

  function test_compactIntervalFormatting() {
    compare(TipModel.formatIntervalMinutes(72), "1h+")
    compare(TipModel.formatIntervalMinutes(2880), "2d")
    compare(TipModel.formatIntervalMinutes(27 * 1440 + 720), "27d+")
    compare(TipModel.formatIntervalMinutes(45 * 1440), "1mo+")
    compare(TipModel.formatIntervalMinutes(90 * 1440), "3mo")
    compare(TipModel.formatIntervalMinutes(400 * 1440), "1y+")
    compare(TipModel.formatIntervalMinutes(730 * 1440), "2y")
  }

  function test_goodIntervalGrowsWithEase() {
    var previous = { dueAt: 0, intervalMinutes: 1440, ease: 2.5, repetitions: 1, lapses: 0 }
    var card = TipModel.scheduledCard(previous, "good", 1000)
    compare(card.intervalMinutes, 3600)
    compare(card.repetitions, 2)
  }

  function test_againResetsRepetitionsAndCountsLapse() {
    var previous = { dueAt: 0, intervalMinutes: 1440, ease: 2.5, repetitions: 3, lapses: 1 }
    var card = TipModel.scheduledCard(previous, "again", 1000)
    compare(card.intervalMinutes, 1)
    compare(card.repetitions, 0)
    compare(card.lapses, 2)
    compare(card.ease, 2.3)
  }

  function test_queueIsEmptyWhenEverythingIsScheduledForLater() {
    var state = TipModel.defaultState()
    state = TipModel.review(state, tips, "one", "good", 0).state
    state = TipModel.review(state, tips, "two", "good", 1).state
    state = TipModel.review(state, tips, "three", "good", 2).state
    compare(TipModel.dueQueue(state, tips, 3).length, 0)
    compare(TipModel.nextDueAt(state, tips, 3), 86400000)
  }

  function test_initialStateUsesCurrentSchemaVersion() {
    var state = TipModel.defaultState()
    compare(state.schemaVersion, 1)
    compare(state.nextNewIndex, 0)
    compare(Object.keys(state.cards).length, 0)
    compare(state.lastNotificationDate, "")
  }

  function test_notificationIsLimitedToOncePerLocalDay() {
    var state = TipModel.defaultState()
    verify(TipModel.shouldNotifyToday(state, "2026-08-25"))
    state.lastNotificationDate = "2026-08-25"
    verify(!TipModel.shouldNotifyToday(state, "2026-08-25"))
    verify(TipModel.shouldNotifyToday(state, "2026-08-26"))
  }

  function test_localDateKey() {
    compare(TipModel.localDateKey(new Date(2026, 7, 25, 23, 45)), "2026-08-25")
  }

  function test_notificationHoursRunFromEightUntilSixteen() {
    verify(!TipModel.withinNotificationHours(new Date(2026, 7, 25, 7, 59)))
    verify(TipModel.withinNotificationHours(new Date(2026, 7, 25, 8, 0)))
    verify(TipModel.withinNotificationHours(new Date(2026, 7, 25, 15, 59)))
    verify(!TipModel.withinNotificationHours(new Date(2026, 7, 25, 16, 0)))
  }

  function test_corruptStateRestartsSafely() {
    var parsed = TipModel.parseState("{not json", tips, 1000)
    compare(parsed.nextNewIndex, 0)
    compare(Object.keys(parsed.cards).length, 0)
  }

  function test_storedStateValidationRejectsCorruptOrIncompleteData() {
    verify(!TipModel.validStoredState("{not json"))
    verify(!TipModel.validStoredState("{}"))
    verify(!TipModel.validStoredState(JSON.stringify({
      schemaVersion: 1, nextNewIndex: 1, cards: {}
    })))
  }

  function test_storedStateValidationAcceptsCurrentState() {
    verify(TipModel.validStoredState(JSON.stringify(TipModel.defaultState())))
  }

  function test_currentSchemaStatePreservesProgress() {
    var storedState = {
      schemaVersion: 1,
      nextNewIndex: 1,
      cards: {
        one: { dueAt: 1000, intervalMinutes: 10, ease: 2.5, repetitions: 1, lapses: 0 }
      },
      lastNotificationDate: "2026-08-25"
    }
    var parsed = TipModel.parseState(JSON.stringify(storedState), tips, 1000)
    compare(parsed.schemaVersion, 1)
    compare(parsed.nextNewIndex, 1)
    compare(parsed.cards.one.dueAt, 1000)
    compare(parsed.lastNotificationDate, "2026-08-25")
  }

  function test_nonCurrentSchemaStateResets() {
    var oldState = {
      schemaVersion: 2,
      nextNewIndex: 1,
      cards: {
        one: { dueAt: 1000, intervalMinutes: 10, ease: 2.5, repetitions: 1, lapses: 0 }
      }
    }
    var parsed = TipModel.parseState(JSON.stringify(oldState), tips, 1000)
    compare(parsed.schemaVersion, 1)
    compare(parsed.nextNewIndex, 0)
    compare(Object.keys(parsed.cards).length, 0)
  }

  function test_waitFormatting() {
    compare(TipModel.formatWait(60000), "1 minute")
    compare(TipModel.formatWait(3600000), "1 hour")
    compare(TipModel.formatWait(3 * 86400000), "3 days")
  }

  function test_actionAllowlist() {
    verify(TipModel.validAction({ kind: "copy", label: "Copy", text: "omarchy commands" }))
    verify(TipModel.validAction({ kind: "exec", label: "Open", argv: ["omarchy-shell", "shell", "summon", "omarchy.menu", "{}"] }))
    verify(!TipModel.validAction({ kind: "exec", label: "No", argv: ["bash", "-c", "anything"] }))
  }

  function test_notificationClickOpensPlugin() {
    verify(TipModel.opensPluginForNotificationAction("default"))
    verify(TipModel.opensPluginForNotificationAction("open\n"))
    verify(!TipModel.opensPluginForNotificationAction(""))
  }

  function test_positionLabelUsesCurrentCardNumber() {
    compare(TipModel.studyPositionLabel({ index: 26, isNew: true }, 60), "Tip 27 / 60")
    compare(TipModel.studyPositionLabel({ index: 26, isNew: false }, 60), "Review · Tip 27 / 60")
    compare(TipModel.studyPositionLabel(null, 60), "")
  }

  function test_expandedCourseContinuesAfterFirstThirtyTips() {
    var expandedTips = []
    for (var i = 0; i < 31; i++)
      expandedTips.push({ id: "tip-" + (i + 1), category: "Test", title: "Tip " + (i + 1), description: "Test" })

    var state = TipModel.defaultState()
    state.nextNewIndex = 30
    var item = TipModel.currentDue(state, expandedTips, 1000)
    compare(item.index, 30)
    compare(item.tip.id, "tip-31")
    verify(item.isNew)
  }
}
