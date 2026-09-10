import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0

Item {
    id: root
    anchors.fill: parent

    property Commands mCommands: VescIf.commands()
    property bool loaded: false
    property bool saving: false

    function sendCode(str) {
        mCommands.sendCustomAppData(str + "\0")
    }

    function getSettings() {
        loaded = false
        sendCode("(send-settings)")
    }

    function setReal(field, value, decimals) {
        var number = Number(value)
        if (Number.isFinite(number)) {
            field.text = number.toFixed(decimals)
        }
    }

    function readReal(field, decimals) {
        var number = Number(field.text)
        if (!Number.isFinite(number)) {
            number = 0
        }
        return number.toFixed(decimals)
    }

    function applySettingsLine(line) {
        var parts = line.split(" ")

        if (parts[0] !== "cruise") {
            return
        }

        cruiseEnabled.checked = parts[1] === "true"
        setReal(cruiseHoldSec, parts[2], 1)
        setReal(cruiseDeadband, parts[3], 2)
        setReal(cruiseMinSpeed, parts[4], 1)
        setReal(cruiseMaxSpeed, parts[5], 1)
        setReal(legalSpeed, parts[6], 1)
        setReal(legalWatt, parts[7], 0)
        loaded = true
    }

    function saveSettings() {
        if (!loaded || saving) {
            return
        }

        saving = true
        sendCode("(save-cruise-settings "
            + (cruiseEnabled.checked ? "true" : "false")
            + " " + readReal(cruiseHoldSec, 1)
            + " " + readReal(cruiseDeadband, 2)
            + " " + readReal(cruiseMinSpeed, 1)
            + " " + readReal(cruiseMaxSpeed, 1)
            + " " + readReal(legalSpeed, 1)
            + " " + readReal(legalWatt, 0)
            + ")")
    }

    Component.onCompleted: {
        getSettings()
    }

    // Lisp may still be starting up, keep asking until it answers
    Timer {
        interval: 2000
        repeat: true
        running: !loaded && !saving
        onTriggered: sendCode("(send-settings)")
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var message = data.toString().trim()

            if (message === "ack") {
                saving = false
                VescIf.emitStatusMessage("Cruise settings saved.", true)
                getSettings()
            } else if (message === "err") {
                saving = false
                VescIf.emitStatusMessage("Saving failed, please try again.", false)
                getSettings()
            } else {
                applySettingsLine(message)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 4

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 4
                    columnSpacing: 8

                    CheckBox {
                        id: cruiseEnabled
                        Layout.columnSpan: 2
                        text: "Cruise Control"
                    }

                    Label { text: "Hold Time (s)" }
                    TextField { id: cruiseHoldSec; Layout.fillWidth: true; validator: DoubleValidator { bottom: 0.0; top: 30.0; decimals: 1 } }

                    Label { text: "Deadband (V)" }
                    TextField { id: cruiseDeadband; Layout.fillWidth: true; validator: DoubleValidator { bottom: 0.01; top: 1.0; decimals: 2 } }

                    Label { text: "Min Speed (km/h)" }
                    TextField { id: cruiseMinSpeed; Layout.fillWidth: true; validator: DoubleValidator { bottom: 0.0; top: 150.0; decimals: 1 } }

                    Label { text: "Max Speed (km/h)" }
                    TextField { id: cruiseMaxSpeed; Layout.fillWidth: true; validator: DoubleValidator { bottom: 0.0; top: 150.0; decimals: 1 } }

                    Label { text: "Legal Speed (km/h)"; Layout.columnSpan: 2; font.bold: true }
                    TextField { id: legalSpeed; Layout.fillWidth: true; validator: DoubleValidator { bottom: 0.0; top: 150.0; decimals: 1 } }

                    Label { text: "Legal Power (W)" }
                    TextField { id: legalWatt; Layout.fillWidth: true; validator: DoubleValidator { bottom: 0.0; top: 20000.0; decimals: 0 } }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                Layout.fillWidth: true
                text: "Load"
                enabled: !saving
                onClicked: getSettings()
            }

            Button {
                Layout.fillWidth: true
                text: "Save"
                enabled: loaded && !saving
                onClicked: saveSettings()
            }

            Button {
                Layout.fillWidth: true
                text: "Reset"
                enabled: loaded && !saving
                onClicked: sendCode("(restore-settings-ui)")
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: !loaded || saving
        visible: running
    }
}
