"""PenCanvas — vertical pen SVG with 3 clickable button overlays."""
from __future__ import annotations
from pathlib import Path
from typing import Optional

from PyQt6.QtCore import QPointF, QRect, QRectF, QSize, Qt, pyqtSignal
from PyQt6.QtGui import QColor, QFont, QPainter, QPen, QPainterPath
from PyQt6.QtSvg import QSvgRenderer
from PyQt6.QtWidgets import QToolTip, QWidget

from gui.theme import (
    BG, ACCENT, ACCENT_CYAN, TEXT_FAINT,
    qc, qc_alpha,
)

# Must match pen.svg viewBox
_SVG_W = 100.0
_SVG_H = 405.0

# Hit zones in SVG coords (x, y, w, h, rx) — rx matches pen.svg outer rects
_BTN_SVG: tuple[tuple[float, float, float, float, float], ...] = (
    (41, 207, 18, 18, 8.0),   # Barrel — svg rx=8
    (41, 234, 18, 18, 8.0),   # Rocker ↑ (housing segment)
    (41, 257, 18, 20, 8.0),   # Rocker ↓
)

_POPUP_GAP = 14


class PenCanvas(QWidget):
    slot_clicked = pyqtSignal(int)
    empty_clicked = pyqtSignal()

    def __init__(self, pen_buttons: list[dict], pen_svg: Path, parent=None):
        super().__init__(parent)
        self._pen_btns = pen_buttons
        self._renderer: Optional[QSvgRenderer] = None
        if pen_svg.exists():
            self._renderer = QSvgRenderer(str(pen_svg))

        cap = len(self._pen_btns)
        self._slots: list[tuple[str, str, str]] = [("", "", "")] * cap
        self._hovered = -1
        self._selected = -1
        self._editor_rect: Optional[QRectF] = None

        self.setMinimumSize(280, 460)
        self.setMouseTracking(True)
        self.setAttribute(Qt.WidgetAttribute.WA_OpaquePaintEvent)

    # ── public API (mirrors TabletCanvas interface) ───────────────────────────

    def set_profile(self, slots: list[tuple[str, str, str]], active: bool = False) -> None:
        cap = len(self._slots)
        self._slots = (slots + [("", "", "")] * cap)[:cap]
        self.update()

    def clear(self) -> None:
        self._slots = [("", "", "")] * len(self._slots)
        self._selected = -1
        self._editor_rect = None
        self.update()

    def set_selected_slot(self, sid: int) -> None:
        self._selected = sid
        self.update()

    def set_editor_rect(self, rect: Optional[QRect | QRectF]) -> None:
        self._editor_rect = QRectF(rect) if rect is not None else None

    def _slot_name(self, sid: int) -> str:
        for pb in self._pen_btns:
            if pb["id"] == sid:
                return f'Pen – {pb["label"]}'
        return f"Slot {sid}"

    def slot_mode(self, _sid: int) -> str:
        return "button"

    def slot_members(self, sid: int) -> tuple[int, ...]:
        return (sid,)

    # ── geometry ──────────────────────────────────────────────────────────────

    def _pen_rect(self) -> QRectF:
        """SVG render rect, centered, aspect-ratio-preserved."""
        pad = 24
        aw = self.width()  - pad * 2
        ah = self.height() - pad * 2
        scale = min(aw / _SVG_W, ah / _SVG_H)
        rw = _SVG_W * scale
        rh = _SVG_H * scale
        return QRectF(
            (self.width()  - rw) / 2,
            (self.height() - rh) / 2,
            rw, rh,
        )

    def _svg_to_widget(self, sx: float, sy: float,
                       sw: float, sh: float, pr: QRectF) -> QRectF:
        sx_scale = pr.width()  / _SVG_W
        sy_scale = pr.height() / _SVG_H
        return QRectF(
            pr.x() + sx * sx_scale,
            pr.y() + sy * sy_scale,
            sw * sx_scale,
            sh * sy_scale,
        )

    def _btn_spec(self, pr: QRectF) -> list[tuple[QRectF, float]]:
        out: list[tuple[QRectF, float]] = []
        sx_scale = pr.width() / _SVG_W
        for spec in _BTN_SVG:
            sx, sy, sw, sh, rx_svg = spec
            r = self._svg_to_widget(sx, sy, sw, sh, pr)
            rx_px = rx_svg * sx_scale
            out.append((r, rx_px))
        return out

    def _button_rects(self, pr: QRectF) -> list[QRectF]:
        return [t[0] for t in self._btn_spec(pr)]

    def _slot_index(self, sid: int) -> int:
        for i, pb in enumerate(self._pen_btns):
            if pb["id"] == sid:
                return i
        return -1

    def _slot(self, sid: int) -> tuple[str, str, str]:
        idx = self._slot_index(sid)
        return self._slots[idx] if idx >= 0 else ("", "", "")

    def popup_geometry(self, sid: int, size: QSize) -> QRect:
        pr = self._pen_rect()
        idx = self._slot_index(sid)
        if idx < 0 or idx >= len(_BTN_SVG):
            return QRect(20, 20, size.width(), size.height())
        btn = self._btn_spec(pr)[idx][0]
        # popup goes to the LEFT of the buttons
        x = int(btn.left() - size.width() - _POPUP_GAP)
        if x < 8:
            x = int(btn.right() + _POPUP_GAP)
        y = max(8, min(
            int(btn.center().y() - size.height() / 2),
            self.height() - size.height() - 8,
        ))
        return QRect(x, y, size.width(), size.height())

    # ── paint ─────────────────────────────────────────────────────────────────

    def paintEvent(self, _) -> None:
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.fillRect(self.rect(), qc(BG))

        pr = self._pen_rect()
        if self._renderer and self._renderer.isValid():
            self._renderer.render(p, pr)
        else:
            p.setPen(qc(TEXT_FAINT))
            p.setFont(QFont("sans-serif", 10))
            p.drawText(self.rect(), Qt.AlignmentFlag.AlignCenter, "pen.svg missing")

        for (rect, rx), pb in zip(self._btn_spec(pr), self._pen_btns):
            self._draw_overlay(p, rect, rx, pb["id"])

        p.end()

    def _draw_overlay(self, p: QPainter, r: QRectF, rx: float, sid: int) -> None:
        _, combo, _ = self._slot(sid)
        bound = bool(combo)
        hov = self._hovered == sid
        sel = self._selected == sid

        path = QPainterPath()
        path.addRoundedRect(r, rx, rx)

        if hov:
            p.setPen(QPen(qc(ACCENT), 1.8))
            p.setBrush(qc_alpha(ACCENT, 65))
            p.drawPath(path)
        elif sel:
            p.setPen(QPen(qc(ACCENT_CYAN), 1.7))
            p.setBrush(qc_alpha(ACCENT_CYAN, 50))
            p.drawPath(path)
        elif bound:
            p.setPen(QPen(qc_alpha(ACCENT, 140), 1.2))
            p.setBrush(qc_alpha(ACCENT, 32))
            p.drawPath(path)

    # ── mouse ─────────────────────────────────────────────────────────────────

    def mouseMoveEvent(self, event) -> None:
        pr = self._pen_rect()
        pos = QPointF(event.pos())
        sid = -1
        for rect, pb in zip(self._button_rects(pr), self._pen_btns):
            if rect.contains(pos):
                sid = pb["id"]
                break
        if sid != self._hovered:
            self._hovered = sid
            self.update()
            if sid >= 0:
                _, combo, label = self._slot(sid)
                name = self._slot_name(sid)
                tip = f"{name}: {label or combo}" if (combo or label) else f"{name}: unbound"
                QToolTip.showText(event.globalPosition().toPoint(), tip, self)

    def leaveEvent(self, _) -> None:
        if self._hovered != -1:
            self._hovered = -1
            self.update()

    def mousePressEvent(self, event) -> None:
        if event.button() != Qt.MouseButton.LeftButton:
            return
        pr = self._pen_rect()
        pos = QPointF(event.pos())
        for rect, pb in zip(self._button_rects(pr), self._pen_btns):
            if rect.contains(pos):
                self.slot_clicked.emit(pb["id"])
                return
        self.empty_clicked.emit()
