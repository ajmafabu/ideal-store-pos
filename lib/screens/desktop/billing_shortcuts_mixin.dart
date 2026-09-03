import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

mixin BillingShortcutsMixin<T extends StatefulWidget> on State<T> {
  // Abstract methods — the parent screen must implement these
  void onF2();
  void onF3();
  void onF4();
  void onF5();
  void onF6();
  void onF7();
  void onF8();
  void onF9();
  void onF10();
  void onF11();
  void onF12();
  void onCtrlShiftN();
  void onCtrlD();
  void onCtrlDelete();
  void onShiftEnter();
  void onEnter();
  void onTab(bool isShift);
  void onCtrlTab();
  void onArrowDown();
  void onArrowUp();
  void onDelete();
  void onPlus();
  void onMinus();
  void onEscape();
  void onResetInactivityTimer();

  bool get isProcessing;
  bool get hasActiveSessionItems;
  bool get isSearchFocused;
  bool get hasSearchText;
  bool get hasSelectedProduct;
  bool get isQtyFocused;
  bool get isPriceFocused;
  bool get isTotalFocused;
  bool get isCostFocused;
  bool get hasSelectedCartIndex;
  bool get showResults;

  void handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (isProcessing) return;

    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    onResetInactivityTimer();

    // ── F-KEYS ──
    if (key == LogicalKeyboardKey.f2) {
      onF2();
      return;
    }
    if (key == LogicalKeyboardKey.f4) {
      onF4();
      return;
    }
    if (key == LogicalKeyboardKey.f5) {
      if (hasActiveSessionItems) onF5();
      return;
    }
    if (key == LogicalKeyboardKey.f6) {
      if (hasActiveSessionItems) onF6();
      return;
    }
    if (key == LogicalKeyboardKey.f7) {
      onF7();
      return;
    }
    if (key == LogicalKeyboardKey.f8) {
      if (hasActiveSessionItems) onF8();
      return;
    }
    if (key == LogicalKeyboardKey.f9) {
      if (hasActiveSessionItems) onF9();
      return;
    }
    if (key == LogicalKeyboardKey.f10) {
      if (hasActiveSessionItems) onF10();
      return;
    }
    if (key == LogicalKeyboardKey.f11) {
      if (hasActiveSessionItems) onF11();
      return;
    }
    if (key == LogicalKeyboardKey.f12) {
      onF12();
      return;
    }
    if (key == LogicalKeyboardKey.f3) {
      onF3();
      return;
    }

    // ── CTRL+SHIFT+N → New product ──
    if (isCtrl && isShift && key == LogicalKeyboardKey.keyN) {
      onCtrlShiftN();
      return;
    }

    // ── CTRL+D → New customer ──
    if (isCtrl && key == LogicalKeyboardKey.keyD) {
      onCtrlD();
      return;
    }

    // ── CTRL+DELETE → Clear entire cart ──
    if (isCtrl && key == LogicalKeyboardKey.delete) {
      if (hasActiveSessionItems) onCtrlDelete();
      return;
    }

    // ── SHIFT+ENTER → Complete sale ──
    if (key == LogicalKeyboardKey.enter && isShift) {
      onShiftEnter();
      return;
    }

    // ── ENTER (no shift) — skip if an entry TextField has focus (handled by onSubmitted) ──
    if (key == LogicalKeyboardKey.enter) {
      if (!isQtyFocused && !isPriceFocused && !isTotalFocused && !isCostFocused) {
        onEnter();
      }
      return;
    }

    // ── TAB → Next field ──
    if (key == LogicalKeyboardKey.tab && !isCtrl && !isAlt) {
      onTab(isShift);
      return;
    }

    // ── CTRL+TAB → Jump to payment panel ──
    if (key == LogicalKeyboardKey.tab && isCtrl) {
      onCtrlTab();
      return;
    }

    // ── ARROW UP / DOWN → navigate search results & cart ──
    if (key == LogicalKeyboardKey.arrowDown) {
      onArrowDown();
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      onArrowUp();
      return;
    }

    // ── DELETE / BACKSPACE → delete cart item ──
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (!hasSearchText &&
          !hasSelectedProduct &&
          !isQtyFocused &&
          !isPriceFocused &&
          !isTotalFocused &&
          !isCostFocused) {
        onDelete();
      }
      return;
    }

    // ── + / - → increment/decrement qty on selected cart item ──
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      if (hasSelectedCartIndex && !hasSelectedProduct && !hasSearchText) {
        onPlus();
      }
      return;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      if (hasSelectedCartIndex && !hasSelectedProduct && !hasSearchText) {
        onMinus();
      }
      return;
    }

    // ── ESCAPE → cancel edit / clear search / back to search ──
    if (key == LogicalKeyboardKey.escape) {
      onEscape();
      return;
    }
  }
}
