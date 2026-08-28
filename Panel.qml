import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "TipModel.js" as TipModel

Panel {
  id: root
  moduleName: "yarikov.omatips"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property var studyItem: service ? service.currentItem : null
  readonly property var tip: studyItem ? studyItem.tip : null
  readonly property var barIdentity: hostWidget || root

  function openLatest() {
    if (!service || !service.hasStudyItem) return
    service.recordPanelOpened()
    controller.show()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function open() { openLatest() }
  function close() { controller.hide() }
  function grade(rating) {
    if (service) service.reviewCurrent(rating)
  }
  function ratingIntervalLabel(rating) {
    var card = studyItem ? studyItem.card : null
    var now = service ? service.nowMs : 0
    return TipModel.ratingIntervalLabel(card, rating, now)
  }
  function runAction() {
    if (service && tip && tip.action) service.runAction(tip)
  }
  function actionLabel() {
    var currentTip = tip
    var action = currentTip ? currentTip.action : null
    return action && action.label ? String(action.label) : ""
  }

  Connections {
    target: root.service
    function onCurrentItemChanged() {
      if (root.opened && (!root.service || !root.service.hasStudyItem)) root.close()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(520))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.runAction()
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.barIdentity, direction)
      }
      onTextKey: function(text) {
        if (text === "1") root.grade("again")
        else if (text === "2") root.grade("hard")
        else if (text === "3") root.grade("good")
        else if (text === "4") root.grade("easy")
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: root.studyItem && root.studyItem.isNew ? "NEW OMARCHY TIP" : "REVIEW"
              color: Color.accent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - progress.implicitWidth - parent.spacing * 2); height: 1 }

            Text {
              id: progress
              text: root.service ? TipModel.studyPositionLabel(root.studyItem, root.service.totalTips) : ""
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            width: parent.width
            text: root.tip ? String(root.tip.category).toUpperCase() : "LOADING"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          Text {
            width: parent.width
            text: root.tip ? root.tip.title : "Preparing your study queue…"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
          }

          BorderSurface {
            width: parent.width
            implicitHeight: exampleText.implicitHeight + Style.space(20)
            visible: !!(root.tip && (root.tip.shortcut || root.tip.command))
            color: Style.normalFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.bar ? root.bar.foreground : Color.foreground, Color.accent)
            radius: Style.cornerRadius

            Text {
              id: exampleText
              anchors.fill: parent
              anchors.margins: Style.space(10)
              text: root.tip ? (root.tip.shortcut || root.tip.command || "") : ""
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              wrapMode: Text.WrapAnywhere
              verticalAlignment: Text.AlignVCenter
            }
          }

          Button {
            visible: root.actionLabel() !== ""
            text: root.actionLabel()
            foreground: root.bar ? root.bar.foreground : Color.foreground
            bordered: true
            enabled: !!root.service && !root.service.actionBusy
            onClicked: root.runAction()
          }

          Text {
            width: parent.width
            text: "How well did you remember this?"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: [
                { rating: "again", label: "1 · Again" },
                { rating: "hard", label: "2 · Hard" },
                { rating: "good", label: "3 · Good" },
                { rating: "easy", label: "4 · Easy" }
              ]

              Button {
                required property var modelData
                width: (content.width - 3 * Style.space(6)) / 4
                text: modelData.label + "  " + root.ratingIntervalLabel(modelData.rating)
                foreground: root.bar ? root.bar.foreground : Color.foreground
                accent: Color.accent
                bordered: true
                onClicked: root.grade(modelData.rating)
              }
            }
          }

          Text {
            width: parent.width
            text: root.actionLabel() !== ""
              ? "Press 1–4 to rate · Enter to run action · Esc to close"
              : "Press 1–4 to rate · Esc to close"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.55)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
