import QtQuick 2.15

Item {
    property string pkgName: "VESC Cruise Control"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "cruise_control.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "vesc_cruise_control.vescpkg"

    function isCompatible (fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase()
        return hwType === "vesc"
    }
}
