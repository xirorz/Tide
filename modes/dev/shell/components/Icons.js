.pragma library
// Stroke icons from the design, on a 24x24 grid. Arcs are written out in full
// (the design's compact SVG flags like "0116" are expanded) so Qt parses them.

function rect(x, y, w, h, r) {
    return "M" + (x + r) + " " + y + " H" + (x + w - r) +
        " A" + r + " " + r + " 0 0 1 " + (x + w) + " " + (y + r) +
        " V" + (y + h - r) +
        " A" + r + " " + r + " 0 0 1 " + (x + w - r) + " " + (y + h) +
        " H" + (x + r) +
        " A" + r + " " + r + " 0 0 1 " + x + " " + (y + h - r) +
        " V" + (y + r) +
        " A" + r + " " + r + " 0 0 1 " + (x + r) + " " + y + " Z ";
}
function circle(cx, cy, r) {
    return "M" + (cx - r) + " " + cy +
        " A" + r + " " + r + " 0 1 0 " + (cx + r) + " " + cy +
        " A" + r + " " + r + " 0 1 0 " + (cx - r) + " " + cy + " Z ";
}

var down = "M9 4 V19 M5 15 L9 19 L13 15";
var up = "M15 20 V5 M11 9 L15 5 L19 9";
var updates = "M12 4 V15 M7 10 L12 15 L17 10 M5 20 H19";
var sparkle = "M12 3 L13.8 7.7 L18.5 9.5 L13.8 11.3 L12 16 L10.2 11.3 L5.5 9.5 L10.2 7.7 Z " +
    "M18 15 L18.8 17.2 L21 18 L18.8 18.8 L18 21 L17.2 18.8 L15 18 L17.2 17.2 Z";
var headset = "M4 15 V12 A8 8 0 0 1 20 12 V15 " + rect(3, 14, 4, 6, 1.5) + rect(17, 14, 4, 6, 1.5);
var mic = rect(9, 3, 6, 11, 3) + "M6 11 A6 6 0 0 0 18 11 M12 17 V21";
var mouse = rect(7, 3, 10, 18, 5) + "M12 7 V10";
var controller = "M7 8 H17 A4 4 0 0 1 21 12 V15 A3 3 0 0 1 15.8 17 L14.5 15.5 H9.5 L8.2 17 A3 3 0 0 1 3 15 V12 A4 4 0 0 1 7 8 Z M8 11 V14 M6.5 12.5 H9.5";
var phone = "M8 3 H16 V21 H8 Z M11 18 H13";
var volume = "M4 10 V14 H8 L13 18 V6 L8 10 Z M16 9 A4 4 0 0 1 16 15 M18.5 6.5 A7.5 7.5 0 0 1 18.5 17.5";
var bell = "M6 16 V11 A6 6 0 0 1 18 11 V16 L19.5 18 H4.5 Z M10 20 H14";
var ethernet = rect(4, 6, 16, 12, 2) + "M8 18 V14 H16 V18 M10 10 H14";
var wifi = "M3 9.5 A13 13 0 0 1 21 9.5 M6.5 13 A8 8 0 0 1 17.5 13 M10 16.5 A3 3 0 0 1 14 16.5 " + circle(12, 19.5, 0.6);
var search = circle(11, 11, 6) + "M20 20 L15.5 15.5";
var close = "M6 6 L18 18 M18 6 L6 18";
var calcCard = rect(5, 3, 14, 18, 3) + "M8 7 H16 M8.5 12 H9.5 M12 12 H12.01 M15.5 12 H15.51 M8.5 16 H9.5 M12 16 H12.01 M15.5 16 H15.51";

// launcher glyphs
var app = "M5 5 H11 V11 H5 Z M13 5 H19 V11 H13 Z M5 13 H11 V19 H5 Z M13 13 H19 V19 H13 Z";
var browser = circle(12, 12, 8) + "M4 12 H20 M12 4 A12 12 0 0 1 12 20 M12 4 A12 12 0 0 0 12 20";
var term = "M4 17 L10 12 L4 7 M12 19 H20";
var cube = "M12 3 L20 7.5 V16.5 L12 21 L4 16.5 V7.5 Z M12 12 L20 7.5 M12 12 V21 M12 12 L4 7.5";
var brush = "M14 4 L20 10 L11 19 H5 V13 Z M12 6 L18 12";
var game = controller;
var film = "M4 5 H20 V19 H4 Z M8 5 V19 M16 5 V19 M4 9 H8 M4 15 H8 M16 9 H20 M16 15 H20";
var printer = "M5 20 H19 M7 20 V9 H17 V20 M9 9 V5 H15 V9 M10 13 H14";
var calc = rect(5, 3, 14, 18, 2) + "M8 7 H16 M9 12 H9.01 M12 12 H12.01 M15 12 H15.01 M9 16 H9.01 M12 16 H12.01 M15 16 H15.01";
var clip = "M9 4 H15 V7 H9 Z M7 5 H5 V20 H19 V5 H17 M8 11 H16 M8 15 H13";
var cap = "M4 8 V5 H7 M17 5 H20 V8 M20 16 V19 H17 M7 19 H4 V16 " + circle(12, 12, 3);
var obs = circle(12, 12, 8) + circle(12, 12, 4);
var power = "M12 3 V11 M7.5 6.5 A7 7 0 1 0 16.5 6.5";
var themes = "M4 6 H20 V18 H4 Z M4 10 H20 M8 14 H11";
var eve = "M12 3 L13.8 7.7 L18.5 9.5 L13.8 11.3 L12 16 L10.2 11.3 L5.5 9.5 L10.2 7.7 Z";

// control center
var sliders = "M4 6 H13 M17 6 H20 M4 12 H7 M11 12 H20 M4 18 H15 M19 18 H20 M15 4 V8 M9 10 V14 M17 16 V20";
var wifiArcs = "M3 9.5 A13 13 0 0 1 21 9.5 M6.5 13 A8 8 0 0 1 17.5 13 M10 16.5 A3 3 0 0 1 14 16.5";
var bluetooth = "M7 7 L17 17 L12 21 V3 L17 7 L7 17";
var cup = "M5 9 H16 V15 A4 4 0 0 1 12 19 H9 A4 4 0 0 1 5 15 Z M16 11 H17.5 A2.5 2.5 0 0 1 17.5 16 H16 M8 3 V6 M11 3 V6";
var check = "M5 12 L10 17 L19 7";
var warn = "M12 4 L21 20 H3 Z M12 10 V14 M12 17 V17";
var pacnew = "M6 4 H15 L18 7 V20 H6 Z M9 10 H15 M9 14 H13";
var lock = "M7 11 V8 A5 5 0 0 1 17 8 V11 M6 11 H18 V20 H6 Z";
var chevronRight = "M9 18 L15 12 L9 6";
var grid = "M5 5 H10 V10 H5 Z M14 5 H19 V10 H14 Z M5 14 H10 V19 H5 Z M14 14 H19 V19 H14 Z";
var chevronDown = "M6 9 L12 15 L18 9";
var chevronUp = "M6 15 L12 9 L18 15";
var speakers = rect(5, 3, 14, 18, 2) + circle(12, 14, 3) + circle(12, 7.5, 1);
var speaker = "M4 10 V14 H8 L13 18 V6 L8 10 Z";
var folder = "M3 7 A2 2 0 0 1 5 5 H9 L11 7 H19 A2 2 0 0 1 21 9 V17 A2 2 0 0 1 19 19 H5 A2 2 0 0 1 3 17 Z";
var corners = "M4 8 V5 H7 M17 5 H20 V8 M20 16 V19 H17 M7 19 H4 V16 ";
var shotRegion = corners + "M9 12 H15 M12 9 V15";
var shotWindow = rect(4, 5, 16, 14, 2) + "M4 9 H20";
var shotScreen = rect(3, 4, 18, 12, 2) + "M9 20 H15 M12 16 V20";
var ocr = corners + "M9 9 H15 M12 9 V16";
var picker = "M14 4 L20 10 L11 19 H5 V13 Z M12 6 L18 12";
var timer = circle(12, 13, 7) + "M12 9 V13 L14 15 M10 3 H14";
var music = "M9 18 V6 L19 4 V16 " + circle(6.5, 18, 2.5) + circle(16.5, 16, 2.5);
var terminal = "M4 17 L10 12 L4 7 M12 19 H20";
// filled glyphs (use with filled: true, stroke 0)
var prev = "M18 6 V18 L9 12 Z M6 6 H8 V18 H6 Z";
var pause = "M7 5 H10.5 V19 H7 Z M13.5 5 H17 V19 H13.5 Z";
var next = "M6 6 V18 L15 12 Z M16 6 H18 V18 H16 Z";
var play = "M8 5 L19 12 L8 19 Z";

// clipboard
var trash = "M5 7 H19 M10 7 V5 H14 V7 M7 7 L8 19 H16 L17 7";
var lines = "M5 6 H19 M5 10 H19 M5 14 H14";
var link = "M10 14 A4 4 0 0 0 15.7 14 L18.7 11 A4 4 0 0 0 13 5.3 L12 6.3 M14 10 A4 4 0 0 0 8.3 10 L5.3 13 A4 4 0 0 0 11 18.7 L12 17.7";

// power menu
var pLock = "M6 11 H18 V20 H6 Z M8.5 11 V8 A3.5 3.5 0 0 1 15.5 8 V11";
var pSleep = "M20 14.5 A8 8 0 0 1 9.5 4 A7 7 0 1 0 20 14.5 Z";
var pLogout = "M10 5 H5 V19 H10 M14 8 L18 12 L14 16 M18 12 H9";
var pRestart = "M20 12 A8 8 0 1 1 17.7 6.4 M20 4 V9 H15";
var pShutdown = "M12 3 V11 M7.5 6.5 A7 7 0 1 0 16.5 6.5";

// Eve live
var micOff = rect(9, 3, 6, 11, 3) + "M6 11 A6 6 0 0 0 18 11 M12 17 V21 M4 4 L20 20";
var keyboard = "M3 7 H21 V17 H3 Z M7 11 H7.01 M10 11 H10.01 M13 11 H13.01 M16 11 H16.01 M8 14 H16";
var containers = "M4 4 H20 V11 H4 Z M4 13 H20 V20 H4 Z";
var globe = circle(12, 12, 8) + "M4 12 H20 M12 4 A12 12 0 0 1 12 20 M12 4 A12 12 0 0 0 12 20";
var doc = "M6 4 H15 L18 7 V20 H6 Z M9 10 H15 M9 14 H15";

// lighting
var sun = circle(12, 12, 4) + "M12 3 V5 M12 19 V21 M3 12 H5 M19 12 H21 M5.6 5.6 L7 7 M17 17 L18.4 18.4 M5.6 18.4 L7 17 M17 7 L18.4 5.6";

// resource center
var gauge = "M4 16 A8 8 0 0 1 20 16 M12 16 L16 10 M7 19 H17";
