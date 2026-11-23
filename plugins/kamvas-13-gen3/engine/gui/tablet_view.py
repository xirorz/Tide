"""Visual tablet diagram for the Huion Kamvas 13 — clickable button slots."""
from PyQt6.QtCore import Qt, QRect, QRectF, QPointF, pyqtSignal
from PyQt6.QtGui import (
    QColor, QFont, QPainter, QPen, QBrush,
    QLinearGradient, QPainterPath, QFontMetrics,
)
from PyQt6.QtWidgets import QWidget, QToolTip

# ── layout constants (all as fractions of drawn tablet rect) ──────────────────
_STRIP_FRAC   = 0.148   # button strip width  / tablet width
_MARGIN_FRAC  = 0.030   # outer margin        / tablet dimension
_BTN_GAP      = 0.008   # gap between buttons / tablet height
_WHEEL_FRAC   = 0.110   # touch-bar height    / tablet height

# Colours
_COL_BODY     = QColor("#1c1c1c")
_COL_BEZEL    = QColor("#141414")
_COL_SCREEN   = QColor("#0d0d0d")
_COL_SCREEN_H = QColor("#1a1a2a")      # screen tint when profile active
_COL_BTN_IDLE = QColor("#272727")
_COL_BTN_BIND = QColor("#1e3a58")
_COL_BTN_HVR  = QColor("#2e4f70")
_COL_BTN_BORD = QColor("#3a3a3a")
_COL_BTN_BORD_BIND = QColor("#4a7aaa")
_COL_WHEEL    = QColor("#222222")
_COL_WHEEL_BD = QColor("#444444")
_COL_NUM      = QColor("#555555")
_COL_LABEL    = QColor("#c8c8c8")
_COL_SUB      = QColor("#7a9abf")
_COL_EMPTY    = QColor("#3a3a3a")
_COL_ACTIVE   = QColor("#5599cc")


class TabletView(QWidget):
    """Draws a schematic of the Huion Kamvas 13 and exposes 8 clickable button slots."""

    # Emitted when the user clicks a slot (0-7 = express keys, 8 = touch bar)
    slot_clicked = pyqtSignal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(560, 290)
        self.setMouseTracking(True)

        # List of 8 slots: (keycode_name, combo, label)
        self._slots: list[tuple[str, str, str]] = [("", "", "")] * 8
        self._hovered: int = -1
        self._profile_active: bool = False

    # ── public API ─────────────────────────────────────────────────────────────

    def set_profile(self, slots: list[tuple[str, str, str]], active: bool) -> None:
        """
        Update displayed bindings.
        slots: list of up to 8 (keycode, combo, label) tuples.
        active: whether this profile is the currently live one.
        """
        self._slots = (slots + [("", "", "")] * 8)[:8]
        self._profile_active = active
        self.update()

    def clear(self) -> None:
        self._slots = [("", "", "")] * 8
        self._profile_active = False
        self.update()

    # ── geometry helpers ───────────────────────────────────────────────────────

    def _tablet_rect(self) -> QRectF:
        """The outer tablet body rectangle."""
        w, h = self.width(), self.height()
        pad = min(w, h) * 0.04
        return QRectF(pad, pad, w - pad * 2, h - pad * 2)

    def _strip_rect(self, tr: QRectF) -> QRectF:
        """Left button-strip area."""
        sw = tr.width() * _STRIP_FRAC
        m = tr.height() * _MARGIN_FRAC
        return QRectF(tr.x() + m, tr.y() + m, sw - m, tr.height() - m * 2)

    def _screen_rect(self, tr: QRectF) -> QRectF:
        sw = tr.width() * _STRIP_FRAC
        m = tr.height() * _MARGIN_FRAC
        gap = tr.width() * 0.008
        return QRectF(
            tr.x() + sw + gap,
            tr.y() + m,
            tr.width() - sw - gap - m,
            tr.height() - m * 2,
        )

    def _button_rects(self, tr: QRectF) -> list[QRect]:
        """Returns 8 button QRects (slots 0-7)."""
        sr = self._strip_rect(tr)
        gap = tr.height() * _BTN_GAP
        wheel_h = tr.height() * _WHEEL_FRAC
        total_btn_h = sr.height() - wheel_h - gap * 9  # 4 above, 4 below, gaps
        btn_h = total_btn_h / 8
        btn_w = sr.width() * 0.88
        btn_x = int(sr.x() + (sr.width() - btn_w) / 2)

        rects: list[QRect] = []
        # Slots 0-3 above the touch bar
        y = sr.y() + gap
        for i in range(4):
            rects.append(QRect(btn_x, int(y), int(btn_w), int(btn_h)))
            y += btn_h + gap

        # Skip the touch-bar zone
        y += wheel_h + gap

        # Slots 4-7 below
        for i in range(4):
            rects.append(QRect(btn_x, int(y), int(btn_w), int(btn_h)))
            y += btn_h + gap

        return rects

    def _wheel_rect(self, tr: QRectF, btn_rects: list[QRect]) -> QRect:
        """The touch-bar/wheel strip between slots 3 and 4."""
        if len(btn_rects) < 5:
            return QRect()
        sr = self._strip_rect(tr)
        gap = tr.height() * _BTN_GAP
        top = btn_rects[3].bottom() + gap
        bot = btn_rects[4].top() - gap
        bx = int(sr.x() + sr.width() * 0.06)
        bw = int(sr.width() * 0.88)
        return QRect(bx, int(top), bw, int(bot - top))

    # ── painting ───────────────────────────────────────────────────────────────

    def paintEvent(self, _) -> None:
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setRenderHint(QPainter.RenderHint.TextAntialiasing)

        tr = self._tablet_rect()
        btn_rects = self._button_rects(tr)
        whl = self._wheel_rect(tr, btn_rects)
        scr = self._screen_rect(tr)

        self._draw_body(p, tr)
        self._draw_screen(p, scr)
        self._draw_wheel(p, whl)
        self._draw_buttons(p, btn_rects)

        p.end()

    def _draw_body(self, p: QPainter, tr: QRectF) -> None:
        # Shadow
        shadow = QRectF(tr.x() + 3, tr.y() + 4, tr.width(), tr.height())
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(0, 0, 0, 60))
        p.drawRoundedRect(shadow, 14, 14)

        # Body gradient
        grad = QLinearGradient(tr.topLeft(), tr.bottomLeft())
        grad.setColorAt(0.0, QColor("#242424"))
        grad.setColorAt(1.0, QColor("#171717"))
        p.setBrush(QBrush(grad))
        p.setPen(QPen(QColor("#333333"), 1.2))
        p.drawRoundedRect(tr, 12, 12)

    def _draw_screen(self, p: QPainter, scr: QRectF) -> None:
        # Screen bezel
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(_COL_BEZEL)
        p.drawRoundedRect(scr.adjusted(-3, -3, 3, 3), 7, 7)

        # Screen surface
        if self._profile_active:
            grad = QLinearGradient(scr.topLeft(), scr.bottomRight())
            grad.setColorAt(0.0, QColor("#0e1520"))
            grad.setColorAt(1.0, QColor("#0a0f18"))
            p.setBrush(QBrush(grad))
        else:
            p.setBrush(_COL_SCREEN)
        p.drawRoundedRect(scr, 5, 5)

        # Brand text
        p.setPen(QColor("#2a2a3a" if not self._profile_active else "#1e3050"))
        fnt = QFont("sans-serif", int(scr.height() * 0.12), QFont.Weight.Bold)
        p.setFont(fnt)
        p.drawText(scr.toRect(), Qt.AlignmentFlag.AlignCenter, "KAMVAS 13")

        # Active glow rim
        if self._profile_active:
            pen = QPen(_COL_ACTIVE, 1.5)
            p.setPen(pen)
            p.setBrush(Qt.BrushStyle.NoBrush)
            p.drawRoundedRect(scr, 5, 5)

    def _draw_wheel(self, p: QPainter, whl: QRect) -> None:
        if whl.isEmpty():
            return
        p.setPen(QPen(_COL_WHEEL_BD, 1))
        grad = QLinearGradient(QPointF(whl.left(), whl.top()),
                               QPointF(whl.left(), whl.bottom()))
        grad.setColorAt(0, QColor("#2a2a2a"))
        grad.setColorAt(1, QColor("#1e1e1e"))
        p.setBrush(QBrush(grad))
        p.drawRoundedRect(QRectF(whl), 4, 4)

        # Arrows
        p.setPen(QColor("#555"))
        fnt = QFont("monospace", max(6, whl.height() // 3))
        p.setFont(fnt)
        left_r = QRect(whl.x(), whl.y(), whl.width() // 3, whl.height())
        right_r = QRect(whl.right() - whl.width() // 3, whl.y(),
                        whl.width() // 3, whl.height())
        p.drawText(left_r, Qt.AlignmentFlag.AlignCenter, "◀")
        p.drawText(right_r, Qt.AlignmentFlag.AlignCenter, "▶")

    def _draw_buttons(self, p: QPainter, rects: list[QRect]) -> None:
        for i, rect in enumerate(rects):
            if i >= len(self._slots):
                break
            keycode, combo, label = self._slots[i]
            bound = bool(combo)
            hovered = i == self._hovered

            # Background
            if hovered:
                bg = _COL_BTN_HVR
                border = _COL_ACTIVE
                bw = 1.5
            elif bound:
                bg = _COL_BTN_BIND
                border = _COL_BTN_BORD_BIND
                bw = 1.0
            else:
                bg = _COL_BTN_IDLE
                border = _COL_BTN_BORD
                bw = 0.8

            p.setPen(QPen(border, bw))
            p.setBrush(bg)
            p.drawRoundedRect(QRectF(rect), 3, 3)

            # Slot number (top-left micro)
            num_fnt = QFont("monospace", max(5, rect.height() // 6))
            p.setFont(num_fnt)
            p.setPen(_COL_NUM)
            p.drawText(
                QRect(rect.x() + 2, rect.y() + 1, rect.width(), rect.height() // 3),
                Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop,
                str(i + 1),
            )

            if not bound:
                # "+" hint
                p.setPen(_COL_EMPTY)
                hint_fnt = QFont("sans-serif", max(7, rect.height() // 4))
                p.setFont(hint_fnt)
                p.drawText(rect, Qt.AlignmentFlag.AlignCenter, "+")
            else:
                text = label if label else combo
                if combo == "__passthrough__":
                    text = "pass-through"

                # Primary text
                inner = rect.adjusted(3, rect.height() // 4, -3, -2)
                p.setPen(_COL_LABEL)
                main_fnt = QFont("sans-serif", max(6, rect.height() // 5),
                                 QFont.Weight.Bold)
                p.setFont(main_fnt)
                p.drawText(inner, Qt.AlignmentFlag.AlignCenter |
                           Qt.TextFlag.TextWordWrap, text)

                # Keycode sub-label (bottom)
                if keycode:
                    sub_fnt = QFont("monospace", max(5, rect.height() // 7))
                    p.setFont(sub_fnt)
                    p.setPen(_COL_SUB)
                    sub_r = QRect(rect.x(), rect.bottom() - rect.height() // 5,
                                  rect.width(), rect.height() // 5)
                    p.drawText(sub_r, Qt.AlignmentFlag.AlignHCenter |
                               Qt.AlignmentFlag.AlignBottom,
                               keycode.replace("KEY_", ""))

    # ── mouse events ───────────────────────────────────────────────────────────

    def mouseMoveEvent(self, event) -> None:
        pos = event.pos()
        tr = self._tablet_rect()
        for i, rect in enumerate(self._button_rects(tr)):
            if rect.contains(pos):
                if self._hovered != i:
                    self._hovered = i
                    self.update()
                    # Tooltip
                    kc, combo, lbl = self._slots[i]
                    if combo:
                        tip = f"Button {i+1}: {lbl or combo}"
                        if kc:
                            tip += f"\nTablet key: {kc}"
                    else:
                        tip = f"Button {i+1}: click to assign"
                    QToolTip.showText(event.globalPosition().toPoint(), tip, self)
                return
        if self._hovered != -1:
            self._hovered = -1
            self.update()

    def leaveEvent(self, _) -> None:
        if self._hovered != -1:
            self._hovered = -1
            self.update()

    def mousePressEvent(self, event) -> None:
        if event.button() != Qt.MouseButton.LeftButton:
            return
        pos = event.pos()
        tr = self._tablet_rect()
        for i, rect in enumerate(self._button_rects(tr)):
            if rect.contains(pos):
                self.slot_clicked.emit(i)
                return
