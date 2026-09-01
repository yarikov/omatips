import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "yarikov.omatips"

  readonly property var tipService: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.service = root.tipService
  }

  function open() {
    if (panelLoader.item) panelLoader.item.openLatest()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (opened) close()
    else open()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  visible: tipService && (tipService.hasStudyItem || tipService.courseCompleted)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onTipServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical || !root.tipService || root.tipService.dueReviewCount === 0
      ? "󰌵"
      : "󰌵 " + root.tipService.dueReviewCount
    tooltipText: !root.tipService ? "OmaTips"
      : root.tipService.courseCompleted
        ? "OmaTips · Omarchy Hero"
        : root.tipService.dueReviewCount > 0
        ? "OmaTips · " + root.tipService.dueReviewCount + " reviews due"
        : "OmaTips · New tip available"
    fontSize: root.vertical ? Style.font.icon : Style.font.body
    horizontalMargin: 8.5
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
    }
  }
}
