"""Linux-style menuconfig TUI for templeos-riscv/scripts/kconfig.py.

Arrow keys navigate; Enter opens submenu or edits value; Space toggles bool /
cycles choice; Left/Esc backs out; / searches; ? help; S save; Q quit.
"""
from __future__ import annotations

import os
import sys
import termios
import tty
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Tuple, Union

# Re-use kconfig helpers via late import to avoid circular imports at module load.


@dataclass
class UIItem:
    kind: str  # submenu | choice | sym
    label: str
    sym_name: Optional[str] = None
    choice_id: Optional[str] = None
    submenu: Optional[Any] = None  # Menu
    enabled: bool = True


def _sym_enabled(sym: Any, vals: Dict[str, Any], tokenize: Callable) -> bool:
    if not sym.depends:
        return True
    return all(tokenize(d, vals) for d in sym.depends)


def _choice_enabled(ch: Any, k: Any, vals: Dict[str, Any], tokenize: Callable) -> bool:
    for m in ch.members:
        sym = k.symbols.get(m)
        if sym and _sym_enabled(sym, vals, tokenize):
            return True
    return False


def _build_menu_items(
    k: Any,
    menu: Any,
    vals: Dict[str, Any],
    tokenize: Callable,
) -> List[UIItem]:
    items: List[UIItem] = []
    emitted_choices: set[str] = set()

    for name in menu.symbols:
        sym = k.symbols.get(name)
        if sym is None:
            continue
        if sym.choice:
            if sym.choice in emitted_choices:
                continue
            emitted_choices.add(sym.choice)
            ch = k.choices[sym.choice]
            enabled = _choice_enabled(ch, k, vals, tokenize)
            items.append(
                UIItem(
                    kind="choice",
                    label=ch.prompt or sym.choice,
                    choice_id=sym.choice,
                    enabled=enabled,
                )
            )
        else:
            if not sym.prompt:
                continue
            enabled = _sym_enabled(sym, vals, tokenize)
            label = sym.prompt or name
            items.append(
                UIItem(kind="sym", label=label, sym_name=name, enabled=enabled)
            )

    for child in menu.children:
        items.append(
            UIItem(kind="submenu", label=child.prompt, submenu=child, enabled=True)
        )

    return items


def _build_root_items(
    k: Any,
    vals: Dict[str, Any],
    tokenize: Callable,
) -> List[UIItem]:
    items: List[UIItem] = []
    for entry in k.root_items:
        if entry[0] == "choice":
            cid = entry[1]
            ch = k.choices[cid]
            enabled = _choice_enabled(ch, k, vals, tokenize)
            items.append(
                UIItem(
                    kind="choice",
                    label=ch.prompt or cid,
                    choice_id=cid,
                    enabled=enabled,
                )
            )
        elif entry[0] == "menu":
            m = entry[1]
            items.append(
                UIItem(kind="submenu", label=m.prompt, submenu=m, enabled=True)
            )
        elif entry[0] == "sym":
            name = entry[1]
            sym = k.symbols[name]
            if not sym.prompt:
                continue
            enabled = _sym_enabled(sym, vals, tokenize)
            items.append(
                UIItem(
                    kind="sym",
                    label=sym.prompt or name,
                    sym_name=name,
                    enabled=enabled,
                )
            )
    return items


def _fmt_bool(vals: Dict[str, Any], name: str) -> str:
    return "[*]" if vals.get(name) else "[ ]"


def _choice_selected_label(k: Any, ch: Any, vals: Dict[str, Any]) -> str:
    for m in ch.members:
        if vals.get(m):
            sym = k.symbols.get(m)
            return sym.prompt or m if sym else m
    return "none"


def _fmt_sym_value(k: Any, name: str, vals: Dict[str, Any]) -> str:
    sym = k.symbols[name]
    v = vals.get(name, "")
    if sym.type == "bool":
        if sym.choice:
            return "(*)" if vals.get(name) else "( )"
        return _fmt_bool(vals, name)
    if sym.type == "hex":
        return f"({_fmt_hex_display(v)})"
    if sym.type == "int":
        return f"({v})"
    if sym.type == "string":
        s = str(v).strip('"')
        return f"({s})"
    return f"({v})"


def _fmt_hex_display(v: Any) -> str:
    if isinstance(v, str):
        v = v.strip().strip('"')
        if v.startswith("0x") or v.startswith("0X"):
            return "0x" + v[2:].upper()
        try:
            return f"0x{int(v, 0):X}"
        except ValueError:
            return v
    return f"0x{int(v):X}"


def _line_for_item(
    k: Any,
    item: UIItem,
    vals: Dict[str, Any],
    active: bool,
) -> str:
    prefix = "->" if active else "  "
    if item.kind == "submenu":
        return f"{prefix} {item.label}  --->"
    if item.kind == "choice":
        sel = _choice_selected_label(k, k.choices[item.choice_id], vals)
        return f"{prefix} {item.label}  ({sel})  --->"
    sym = k.symbols[item.sym_name]
    val = _fmt_sym_value(k, item.sym_name, vals)
    if not item.enabled and sym.type == "bool" and not sym.choice:
        val = f"-   {_fmt_bool(vals, item.sym_name)}"
        return f"{prefix} {val} {item.label}"
    return f"{prefix} {val} {item.label}"


class KeyReader:
    def __init__(self) -> None:
        self.fd = sys.stdin.fileno()
        self.old: Optional[List] = None

    def __enter__(self) -> "KeyReader":
        self.old = termios.tcgetattr(self.fd)
        tty.setraw(self.fd)
        return self

    def __exit__(self, *args: Any) -> None:
        if self.old is not None:
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.old)

    def read(self) -> str:
        ch = sys.stdin.read(1)
        if ch == "\x1b":
            ch2 = sys.stdin.read(1)
            if ch2 == "[":
                ch3 = sys.stdin.read(1)
                if ch3 == "A":
                    return "UP"
                if ch3 == "B":
                    return "DOWN"
                if ch3 == "C":
                    return "RIGHT"
                if ch3 == "D":
                    return "LEFT"
                if ch3 == "H":
                    return "HOME"
                if ch3 == "F":
                    ch4 = sys.stdin.read(1)
                    if ch4 == "5":
                        return "END"
            elif ch2 == "O":
                ch3 = sys.stdin.read(1)
                if ch3 == "A":
                    return "UP"
                if ch3 == "B":
                    return "DOWN"
                if ch3 == "C":
                    return "RIGHT"
                if ch3 == "D":
                    return "LEFT"
            return "ESC"
        if ch in ("\r", "\n"):
            return "ENTER"
        if ch == " ":
            return "SPACE"
        if ch in ("q", "Q"):
            return "QUIT"
        if ch in ("s", "S"):
            return "SAVE"
        if ch == "/":
            return "SEARCH"
        if ch in ("?", "h", "H"):
            return "HELP"
        if ch in ("y", "Y"):
            return "YES"
        if ch in ("n", "N"):
            return "NO"
        if ch == "\x03":
            return "CTRL_C"
        return ch


@dataclass
class MenuFrame:
    title: str
    items: List[UIItem]
    cursor: int = 0
    parent_menu: Optional[Any] = None  # Menu or None for root


class MenuConfigTUI:
    def __init__(
        self,
        k: Any,
        vals: Dict[str, Any],
        tokenize: Callable,
        vals_to_preset: Callable,
        resolve: Callable,
        fmt_hex: Callable,
        parse_val: Callable,
        write_config: Callable,
        write_autoconf: Callable,
        config_path: Any,
    ) -> None:
        self.k = k
        self.vals = vals
        self.tokenize = tokenize
        self.vals_to_preset = vals_to_preset
        self.resolve = resolve
        self.fmt_hex = fmt_hex
        self.parse_val = parse_val
        self.write_config = write_config
        self.write_autoconf = write_autoconf
        self.config_path = config_path
        self.stack: List[MenuFrame] = []
        self.search_hits: Optional[List[Tuple[str, str]]] = None
        self.search_query = ""
        self.status = ""
        self.saved = False
        self.quit_without_save = False
        self._push_root()

    def _push_root(self) -> None:
        items = _build_root_items(self.k, self.vals, self.tokenize)
        self.stack.append(
            MenuFrame(title=self.k.mainmenu, items=items, parent_menu=None)
        )

    def _push_menu(self, menu: Any) -> None:
        items = _build_menu_items(self.k, menu, self.vals, self.tokenize)
        self.stack.append(
            MenuFrame(title=menu.prompt, items=items, parent_menu=menu)
        )

    def _push_choice(self, choice_id: str) -> None:
        ch = self.k.choices[choice_id]
        items: List[UIItem] = []
        for m in ch.members:
            sym = self.k.symbols[m]
            enabled = _sym_enabled(sym, self.vals, self.tokenize)
            items.append(
                UIItem(
                    kind="sym",
                    label=sym.prompt or m,
                    sym_name=m,
                    enabled=enabled,
                )
            )
        title = ch.prompt or choice_id
        self.stack.append(
            MenuFrame(title=title, items=items, parent_menu=None)
        )

    def _current(self) -> MenuFrame:
        return self.stack[-1]

    def _rebuild_frame(self, frame: MenuFrame) -> None:
        if frame.parent_menu is None and len(self.stack) == 1:
            frame.items = _build_root_items(self.k, self.vals, self.tokenize)
        elif frame.parent_menu is not None:
            frame.items = _build_menu_items(
                self.k, frame.parent_menu, self.vals, self.tokenize
            )
        # choice submenu: keep items (members don't change with deps)

    def _rebuild_all_frames(self) -> None:
        for frame in self.stack:
            self._rebuild_frame(frame)

    def _clamp_cursor(self) -> None:
        frame = self._current()
        if not frame.items:
            frame.cursor = 0
        else:
            frame.cursor = max(0, min(frame.cursor, len(frame.items) - 1))

    def _resolve_vals(self) -> None:
        preset = self.vals_to_preset(self.vals)
        self.vals = self.resolve(self.k, preset)
        self._rebuild_all_frames()
        self._clamp_cursor()

    def _toggle_bool(self, name: str) -> None:
        sym = self.k.symbols[name]
        if not _sym_enabled(sym, self.vals, self.tokenize):
            self.status = f"{name}: dependency not satisfied"
            return
        self.vals[name] = not self.vals.get(name)
        self._resolve_vals()

    def _set_bool(self, name: str, on: bool) -> None:
        sym = self.k.symbols[name]
        if not _sym_enabled(sym, self.vals, self.tokenize):
            self.status = f"{name}: dependency not satisfied"
            return
        self.vals[name] = on
        self._resolve_vals()

    def _select_choice_member(self, choice_id: str, member: str) -> None:
        ch = self.k.choices[choice_id]
        for m in ch.members:
            self.vals[m] = m == member
        self._resolve_vals()

    def _edit_value(self, name: str) -> None:
        sym = self.k.symbols[name]
        if not _sym_enabled(sym, self.vals, self.tokenize):
            self.status = f"{name}: dependency not satisfied"
            return
        cur = self.vals.get(name, "")
        if sym.type == "bool":
            self._toggle_bool(name)
            return
        # Line editor at bottom (cooked mode briefly)
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        try:
            prompt = f"  {name} [{cur}]: "
            sys.stdout.write(prompt)
            sys.stdout.flush()
            line = sys.stdin.readline().strip()
        finally:
            tty.setraw(fd)
        if not line:
            return
        if sym.type == "hex":
            self.vals[name] = self.fmt_hex(line)
        elif sym.type == "int":
            self.vals[name] = str(int(line, 0))
        else:
            self.vals[name] = line.strip('"')
        self._resolve_vals()

    def _save(self) -> None:
        self.write_config(
            self.config_path, self.vals, self.k._order, self.k.symbols
        )
        self.write_autoconf(self.vals, self.k.symbols)
        self.saved = True
        self.status = "Configuration saved"

    def _search(self) -> None:
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        try:
            sys.stdout.write("  Search (symbol or prompt): ")
            sys.stdout.flush()
            query = sys.stdin.readline().strip().lower()
        finally:
            tty.setraw(fd)
        if not query:
            self.search_hits = None
            return
        self.search_query = query
        hits: List[Tuple[str, str]] = []
        for name, sym in self.k.symbols.items():
            if query in name.lower() or (sym.prompt and query in sym.prompt.lower()):
                hits.append((name, sym.prompt or name))
        self.search_hits = hits
        self.status = f"Search '{query}': {len(hits)} hits (Enter on hit to jump)"

    def _show_help(self, sym_name: Optional[str] = None) -> None:
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        try:
            print()
            if sym_name and sym_name in self.k.symbols:
                sym = self.k.symbols[sym_name]
                print(f"=== {sym_name} ===")
                if sym.prompt:
                    print(sym.prompt)
                print()
                if sym.help:
                    print(sym.help)
                else:
                    print("(no help text)")
            else:
                print("=== menuconfig keys ===")
                print("  Up/Down     navigate")
                print("  Enter/Right open submenu or edit value")
                print("  Space       toggle bool / select choice item")
                print("  Y / N       enable / disable bool")
                print("  Left/Esc    back")
                print("  /           search symbols")
                print("  ?           help (on item or general)")
                print("  S           save .config + headers")
                print("  Q           quit (prompt if unsaved)")
            print()
            input("  Press Enter to continue...")
        finally:
            tty.setraw(fd)

    def _draw(self) -> None:
        frame = self._current()
        lines: List[str] = []
        w = min(78, max(60, os.get_terminal_size().columns - 1))
        bar = "-" * w
        lines.append(bar)
        title = frame.title
        if len(title) > w - 2:
            title = title[: w - 5] + "..."
        lines.append(f"  {title}")
        lines.append(bar)
        if self.search_hits is not None:
            lines.append(f"  Search results for '{self.search_query}':")
            for i, (name, prompt) in enumerate(self.search_hits[:20]):
                mark = "->" if i == frame.cursor else "  "
                lines.append(f"{mark} {name}: {prompt}")
            if len(self.search_hits) > 20:
                lines.append(f"  ... {len(self.search_hits) - 20} more")
        else:
            if not frame.items:
                lines.append("  (empty)")
            for i, item in enumerate(frame.items):
                active = i == frame.cursor
                line = _line_for_item(self.k, item, self.vals, active)
                if len(line) > w:
                    line = line[: w - 3] + "..."
                lines.append(line)
        lines.append(bar)
        hint = "↑↓ navigate  Enter submenu  Space toggle  S save  Q quit  / search  ? help"
        if self.status:
            lines.append(f"  {self.status[:w-4]}")
        lines.append(f"  {hint[:w-4]}")
        # Clear screen and draw
        sys.stdout.write("\x1b[2J\x1b[H")
        sys.stdout.write("\n".join(lines) + "\n")
        sys.stdout.flush()

    def _activate_item(self, item: UIItem) -> None:
        if item.kind == "submenu" and item.submenu is not None:
            self._push_menu(item.submenu)
            self._clamp_cursor()
            self.status = ""
            return
        if item.kind == "choice" and item.choice_id:
            self._push_choice(item.choice_id)
            self._clamp_cursor()
            self.status = ""
            return
        if item.kind == "sym" and item.sym_name:
            sym = self.k.symbols[item.sym_name]
            if sym.choice:
                # Inside choice submenu: select this member
                # Find parent choice
                for ch in self.k.choices.values():
                    if item.sym_name in ch.members:
                        self._select_choice_member(ch.id, item.sym_name)
                        break
            elif sym.type == "bool":
                self._toggle_bool(item.sym_name)
            else:
                self._edit_value(item.sym_name)

    def _handle_key(self, key: str) -> bool:
        """Return False to exit loop."""
        frame = self._current()

        if self.search_hits is not None:
            if key == "UP":
                frame.cursor = max(0, frame.cursor - 1)
            elif key == "DOWN":
                frame.cursor = min(len(self.search_hits) - 1, frame.cursor + 1)
            elif key == "ENTER" and self.search_hits:
                name = self.search_hits[frame.cursor][0]
                sym = self.k.symbols[name]
                if sym.choice:
                    self.search_hits = None
                    self._push_choice(sym.choice)
                else:
                    self.search_hits = None
                    self._edit_value(name)
            elif key in ("ESC", "LEFT", "q", "QUIT"):
                self.search_hits = None
                self.status = ""
            elif key == "HELP":
                if self.search_hits and frame.cursor < len(self.search_hits):
                    self._show_help(self.search_hits[frame.cursor][0])
                else:
                    self._show_help()
            return True

        if not frame.items and key not in ("ESC", "LEFT", "QUIT", "SAVE"):
            if key in ("ESC", "LEFT"):
                if len(self.stack) > 1:
                    self.stack.pop()
            return True

        item = frame.items[frame.cursor] if frame.items else None

        if key == "UP":
            if frame.cursor > 0:
                frame.cursor -= 1
        elif key == "DOWN":
            if frame.cursor < len(frame.items) - 1:
                frame.cursor += 1
        elif key in ("ENTER", "RIGHT"):
            if item:
                self._activate_item(item)
        elif key == "SPACE":
            if item and item.kind == "sym" and item.sym_name:
                sym = self.k.symbols[item.sym_name]
                if sym.choice:
                    for ch in self.k.choices.values():
                        if item.sym_name in ch.members:
                            self._select_choice_member(ch.id, item.sym_name)
                            break
                elif sym.type == "bool":
                    self._toggle_bool(item.sym_name)
                elif item.kind == "choice" and item.choice_id:
                    self._push_choice(item.choice_id)
            elif item and item.kind == "choice":
                self._push_choice(item.choice_id)
        elif key == "YES":
            if item and item.kind == "sym" and item.sym_name:
                sym = self.k.symbols[item.sym_name]
                if sym.type == "bool":
                    self._set_bool(item.sym_name, True)
        elif key == "NO":
            if item and item.kind == "sym" and item.sym_name:
                sym = self.k.symbols[item.sym_name]
                if sym.type == "bool":
                    self._set_bool(item.sym_name, False)
        elif key in ("ESC", "LEFT"):
            if len(self.stack) > 1:
                self.stack.pop()
                self.status = ""
            else:
                return self._confirm_quit()
        elif key == "SAVE":
            self._save()
        elif key == "QUIT":
            return self._confirm_quit()
        elif key == "SEARCH":
            self._search()
            if self.search_hits:
                frame.cursor = 0
        elif key == "HELP":
            if item and item.sym_name:
                self._show_help(item.sym_name)
            elif item and item.choice_id:
                # help for first member with help
                ch = self.k.choices[item.choice_id]
                for m in ch.members:
                    if self.k.symbols[m].help:
                        self._show_help(m)
                        break
                else:
                    self._show_help()
            else:
                self._show_help()
        elif key == "CTRL_C":
            return self._confirm_quit()
        return True

    def _confirm_quit(self) -> bool:
        if self.saved:
            return False
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        try:
            sys.stdout.write("\n  Quit without saving? [y/N] ")
            sys.stdout.flush()
            ans = sys.stdin.readline().strip().lower()
        finally:
            tty.setraw(fd)
        if ans in ("y", "yes"):
            self.quit_without_save = True
            return False
        return True

    def run(self) -> Dict[str, Any]:
        with KeyReader() as kr:
            running = True
            while running:
                self._draw()
                running = self._handle_key(kr.read())
        return self.vals


def run_menuconfig_tui(
    k: Any,
    vals: Dict[str, Any],
    tokenize: Callable,
    vals_to_preset: Callable,
    resolve: Callable,
    fmt_hex: Callable,
    parse_val: Callable,
    write_config: Callable,
    write_autoconf: Callable,
    config_path: Any,
) -> Dict[str, Any]:
    tui = MenuConfigTUI(
        k, vals, tokenize, vals_to_preset, resolve,
        fmt_hex, parse_val, write_config, write_autoconf, config_path,
    )
    return tui.run()


def self_test(k: Any, tokenize: Callable) -> int:
    """Verify tree builds and format strings; returns 0 on success."""
    vals: Dict[str, Any] = {}
    root_items = _build_root_items(k, vals, tokenize)
    if not root_items:
        print("self_test FAIL: empty root", file=sys.stderr)
        return 1
    errors: List[str] = []
    for menu in k.menus:
        items = _build_menu_items(k, menu, vals, tokenize)
        if not items and menu.children:
            errors.append(f"menu '{menu.prompt}' has children but no items")
    for name, sym in k.symbols.items():
        if sym.type == "bool":
            vals[name] = False
    for item in root_items:
        line = _line_for_item(k, item, vals, False)
        if not line.strip():
            errors.append(f"empty line for root item {item}")
    if errors:
        for e in errors:
            print(f"self_test FAIL: {e}", file=sys.stderr)
        return 1
    print(
        f"self_test OK: root={len(root_items)} menus={len(k.menus)} "
        f"symbols={len(k.symbols)} choices={len(k.choices)}"
    )
    return 0
