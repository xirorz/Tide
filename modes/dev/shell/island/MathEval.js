.pragma library
// The launcher's inline math, ported from the design: + - * / ^ % and brackets.

function evalMath(src) {
    const s = String(src).replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/\s+/g, "");
    if (!s || !/^[0-9+\-*/().%^]+$/.test(s) || !/[0-9]/.test(s)) return null;
    let i = 0;
    function expr() { let v = term(); while (s[i] === "+" || s[i] === "-") { const op = s[i++]; const r = term(); v = op === "+" ? v + r : v - r; } return v; }
    function term() { let v = unary(); while (s[i] === "*" || s[i] === "/") { const op = s[i++]; const r = unary(); v = op === "*" ? v * r : v / r; } return v; }
    function unary() { if (s[i] === "-") { i++; return -unary(); } if (s[i] === "+") { i++; return unary(); } return power(); }
    function power() { const b = primary(); if (s[i] === "^") { i++; return Math.pow(b, unary()); } return b; }
    function primary() {
        let v;
        if (s[i] === "(") { i++; v = expr(); if (s[i] !== ")") throw new Error("paren"); i++; }
        else { const m = /^[0-9]*\.?[0-9]+|^[0-9]+\./.exec(s.slice(i)); if (!m) throw new Error("num"); i += m[0].length; v = parseFloat(m[0]); }
        while (s[i] === "%") { i++; v = v / 100; }
        return v;
    }
    try { const v = expr(); if (i !== s.length || !isFinite(v)) return null; return v; } catch (e) { return null; }
}

// "has math": a digit and an operator, like the design
function looksLikeMath(q) {
    return /[0-9]/.test(q) && /[+\-*/^%()]/.test(q);
}

function commas(intStr) {
    return intStr.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// en-US formatting: integers with separators, others to 10 significant digits, at most 8 decimals
function fmt(v) {
    if (Number.isInteger(v)) return (v < 0 ? "-" : "") + commas(String(Math.abs(v)));
    let n = parseFloat(v.toPrecision(10));
    let str = String(parseFloat(n.toFixed(8)));
    const neg = str[0] === "-";
    if (neg) str = str.slice(1);
    const parts = str.split(".");
    return (neg ? "-" : "") + commas(parts[0]) + (parts[1] ? "." + parts[1] : "");
}

// plain value for the clipboard
function plain(v) {
    return String(parseFloat(v.toPrecision(12)));
}
