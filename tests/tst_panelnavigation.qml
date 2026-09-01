import QtQuick
import QtTest
import "../PanelNavigation.js" as Navigation

TestCase {
  name: "PanelNavigation"

  readonly property var ratings: [["again", "hard", "good", "easy"]]
  readonly property var hiddenAnswer: [["showAnswer"]]
  readonly property var lessonWithAction: [["action"], ["again", "hard", "good", "easy"]]
  readonly property var twoButtons: [["cancel", "confirm"]]

  function test_firstReturnsFirstAvailableTarget() {
    compare(Navigation.first(lessonWithAction), "action")
    compare(Navigation.first([]), "")
  }

  function test_horizontalMovementStopsAtEdges() {
    compare(Navigation.move(ratings, "again", -1, 0), "again")
    compare(Navigation.move(ratings, "again", 1, 0), "hard")
    compare(Navigation.move(ratings, "easy", 1, 0), "easy")
  }

  function test_hiddenAnswerKeepsCursorOnRevealButton() {
    compare(Navigation.first(hiddenAnswer), "showAnswer")
    compare(Navigation.move(hiddenAnswer, "showAnswer", -1, 0), "showAnswer")
    compare(Navigation.move(hiddenAnswer, "showAnswer", 0, 1), "showAnswer")
  }

  function test_verticalMovementUsesNearestAvailableColumn() {
    compare(Navigation.move(lessonWithAction, "action", 0, 1), "again")
    compare(Navigation.move(lessonWithAction, "good", 0, -1), "action")
  }

  function test_twoButtonRowsSupportBothDirections() {
    compare(Navigation.move(twoButtons, "cancel", 1, 0), "confirm")
    compare(Navigation.move(twoButtons, "confirm", -1, 0), "cancel")
  }

  function test_unknownTargetStartsAtFirstButton() {
    compare(Navigation.move(ratings, "missing", 1, 0), "again")
    verify(Navigation.contains(ratings, "good"))
    verify(!Navigation.contains(ratings, "missing"))
  }
}
