import QtQuick

// Settings → System → Free up space: a row's button. "here" steps ask for a second
// click (Sure?); "terminal" ones open in your terminal (Clean…).
SBtn {
    property string what
    property string how: "here"
    property string cmd: ""
    property string armed: ""
    signal clean(string what, string how, string cmd)
    label: armed === what ? "Sure?" : how === "terminal" ? "Clean…" : "Clean"
    primary: armed === what
    onClicked: clean(what, how, cmd)
}
