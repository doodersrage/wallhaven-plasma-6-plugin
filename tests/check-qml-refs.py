#!/usr/bin/env python3
"""Static reference check for the wallpaper/plasmoid QML.

QML resolves names at run time, so a function moved to another file (or a
renamed helper) only fails when that code path finally executes -- on
somebody's desktop. qmllint does not look inside untyped JS function bodies,
which is where nearly all of this plugin's logic lives. This script does a
cheap lexical pass instead and fails when:

  * a bare identifier is not declared anywhere in its file (id, property,
    function, signal, parameter, local) and is not a known global;
  * `host.X` / `root.X` names a member the wallpaper root does not have;
  * `engine.X` / `dbus.X` / `dbusHelper.X` names a member that object lacks;
  * `Wallhaven.X` is not a function or variable in wallhaven.js.

  * a Connections block on a KConfig map declares `function onFooChanged()`
    for a capitalized key `Foo`: Qt never calls those (the whole settings
    block of the wallpaper was dead this way). Watch such keys with a binding.

It is a heuristic, not a parser: scopes are approximated per file. That is
enough to catch dangling references, which is the failure it exists for.
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "contents" / "ui"
JS = ROOT / "contents" / "code" / "wallhaven.js"

JS_KEYWORDS = set(
    """break case catch continue default delete do else finally for function if in
    instanceof new return switch this throw try typeof var let const void while
    true false null undefined of""".split()
)
QML_KEYWORDS = set(
    """import as property readonly required alias signal default on pragma component
    enum id""".split()
)
QML_TYPES_AS_VALUES = set("int bool real double string url var color date point size rect list".split())
GLOBALS = set(
    """Qt console Math JSON Date String Number Boolean Array Object Error RegExp
    parseInt parseFloat isNaN isFinite encodeURIComponent decodeURIComponent
    XMLHttpRequest Infinity NaN arguments
    i18n i18nc i18np i18ncp
    parent""".split()
)
# Inherited members used bare. Kept explicit so a typo is not mistaken for one.
INHERITED = {
    "*": set(
        """width height visible opacity enabled x y z scale implicitWidth implicitHeight
        modelData index hovered checked pressed containsMouse availableWidth currentIndex
        easing selectedFolder""".split()
    ),
    # Guarded by `typeof ... !== "undefined"`; provided by the hosting settings dialog.
    "config.qml": set("appearanceRoot".split()),
    "main.qml": set("configuration loading contextualActions".split()),
    "Timer": set("interval running repeat triggeredOnStart start stop restart".split()),
    "Image": set("source status sourceSize grabToImage".split()),
    "FileDialog": set("selectedFile currentFolder".split()),
    "Rectangle": set("color radius".split()),
    "DBusServiceWatcher": set("registered".split()),
    "Loader": set("item status".split()),
    "PlasmoidItem": set("expanded fullRepresentation".split()),
}
# Members every QML object / Item has; valid after `host.` or `root.`.
BASE_MEMBERS = set(
    """width height visible opacity enabled x y z scale parent configuration loading
    contextualActions grabToImage""".split()
)

TOKEN_RE = re.compile(
    r"""
    (?P<ws>\s+)
  | (?P<lc>//[^\n]*)
  | (?P<bc>/\*.*?\*/)
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)
  | (?P<num>0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+)
  | (?P<id>[A-Za-z_$][A-Za-z0-9_$]*)
  | (?P<punct>===|!==|==|!=|<=|>=|&&|\|\||\+\+|--|=>|[{}()\[\];,.:?=+\-*/%<>!&|^~@])
    """,
    re.VERBOSE | re.DOTALL,
)
REGEX_RE = re.compile(r"/(?![*/])(?:\\.|\[(?:\\.|[^\]\\\n])*\]|[^/\\\n])+/[gimsuy]*")
# A `/` after one of these starts a regex literal rather than a division.
REGEX_PREV = set("( , = : [ ! & | ? { } ; return typeof + - * % < > == === != !== && || =>".split())


def tokenize(text: str) -> list[tuple[str, str, int]]:
    """[(kind, value, line)] with whitespace/comments dropped."""
    out: list[tuple[str, str, int]] = []
    pos = 0
    line = 1
    prev = ""
    while pos < len(text):
        if text[pos] == "/" and (not out or prev in REGEX_PREV):
            m = REGEX_RE.match(text, pos)
            if m and not text.startswith("//", pos) and not text.startswith("/*", pos):
                out.append(("regex", m.group(0), line))
                prev = "regex"
                pos = m.end()
                continue
        m = TOKEN_RE.match(text, pos)
        if not m:
            raise SystemExit(f"check-qml-refs: cannot tokenize at line {line}: {text[pos:pos + 40]!r}")
        kind = m.lastgroup or ""
        value = m.group(0)
        if kind not in ("ws", "lc", "bc"):
            out.append((kind, value, line))
            prev = value
        line += value.count("\n")
        pos = m.end()
    return out


class FileInfo:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.tokens = tokenize(path.read_text(encoding="utf-8"))
        self.ids: set[str] = set()
        self.declared: set[str] = set()  # properties/functions/signals/locals/params, any depth
        self.import_aliases: set[str] = set()
        self.types_used: set[str] = set()
        # members declared directly inside each QML object, keyed by its id ("" = root)
        self.members: dict[str, set[str]] = {}
        self.uses: list[tuple[str, int]] = []  # bare identifiers
        self.member_uses: list[tuple[str, str, int]] = []  # (object, member, line)
        self._scan()

    def _scan(self) -> None:
        toks = self.tokens
        n = len(toks)
        # Stack of frames: ("obj", members-set, type-name) or ("js", None, "").
        stack: list[list] = []
        root_seen = False
        i = 0

        def val(j: int) -> str:
            return toks[j][1] if 0 <= j < n else ""

        def kind(j: int) -> str:
            return toks[j][0] if 0 <= j < n else ""

        while i < n:
            k, v, line = toks[i]
            if k == "id" and v == "import" and not stack:
                # import X.Y as Alias  /  import "file.js" as Alias
                j = i + 1
                while j < n and toks[j][2] == line:
                    if val(j) == "as" and kind(j + 1) == "id":
                        self.import_aliases.add(val(j + 1))
                    j += 1
                i = j
                continue
            if k == "punct" and v == "{":
                is_obj = False
                type_name = ""
                # TypeName {   or   Alias.TypeName {
                if kind(i - 1) == "id" and val(i - 1)[:1].isupper():
                    before = val(i - 2)
                    if before == "." and kind(i - 3) == "id":
                        before = val(i - 4)
                    in_object_ctx = not stack or stack[-1][0] == "obj"
                    if in_object_ctx or before in (":", "") :
                        is_obj = True
                        type_name = val(i - 1)
                if is_obj:
                    members: set[str] = set()
                    frame = ["obj", members, type_name, ""]
                    if not root_seen:
                        root_seen = True
                        self.members[""] = members
                    stack.append(frame)
                    self.types_used.add(type_name)
                else:
                    stack.append(["js", None, "", ""])
                i += 1
                continue
            if k == "punct" and v == "}":
                if stack:
                    frame = stack.pop()
                    if frame[0] == "obj" and frame[3]:
                        self.members[frame[3]] = frame[1]
                i += 1
                continue

            in_obj = bool(stack) and stack[-1][0] == "obj"
            if k == "id":
                prev = val(i - 1)
                nxt = val(i + 1)
                if in_obj and v == "id" and nxt == ":" and kind(i + 2) == "id":
                    name = val(i + 2)
                    self.ids.add(name)
                    stack[-1][3] = name
                    i += 3
                    continue
                if in_obj and v in ("property", "signal", "function") or (
                    in_obj and v in ("readonly", "required", "default") and val(i + 1) == "property"
                ):
                    j = i
                    while val(j) in ("readonly", "required", "default"):
                        j += 1
                    word = val(j)
                    if word == "property":
                        # property <type>[<...>] name   |  property alias name
                        j += 1
                        # type may be dotted or list<...>
                        j += 1
                        while val(j) in (".", "<", ">") or (kind(j) == "id" and val(j - 1) in (".", "<")):
                            j += 1
                        name = val(j)
                        if kind(j) == "id":
                            stack[-1][1].add(name)
                            self.declared.add(name)
                            i = j + 1
                            continue
                    elif word in ("signal", "function") and kind(j + 1) == "id":
                        name = val(j + 1)
                        stack[-1][1].add(name)
                        self.declared.add(name)
                        j += 2
                        if val(j) == "(":
                            j = self._params(j)
                        i = j
                        continue
                if v == "function":
                    j = i + 1
                    if kind(j) == "id":
                        self.declared.add(val(j))
                        j += 1
                    if val(j) == "(":
                        j = self._params(j)
                    i = j
                    continue
                if v in ("var", "let", "const") and kind(i + 1) == "id":
                    self.declared.add(val(i + 1))
                    i += 2
                    continue
                if v == "catch" and nxt == "(" and kind(i + 2) == "id":
                    self.declared.add(val(i + 2))
                    i += 3
                    continue
                if v in JS_KEYWORDS or v in QML_KEYWORDS:
                    i += 1
                    continue
                if prev == ".":
                    # member access: record owner.member for known owners
                    if kind(i - 2) == "id" and val(i - 3) != ".":
                        self.member_uses.append((val(i - 2), v, line))
                    i += 1
                    continue
                if nxt == ":" and val(i + 2) != ":":
                    # QML binding target or JS object-literal key / label; but
                    # `cond ? a : b` puts an identifier before ':' too.
                    if not self._in_ternary(i):
                        i += 1
                        continue
                if in_obj and nxt == "." and val(i + 3) == ":":
                    # grouped binding: anchors.fill: / Layout.fillWidth: / icon.name:
                    i += 3
                    continue
                if in_obj and nxt == "{":
                    i += 1  # Type { handled at the brace
                    continue
                self.uses.append((v, line))
            i += 1

    def _params(self, j: int) -> int:
        """Record parameter names of the list starting at '(' ; return index after ')'."""
        toks = self.tokens
        depth = 0
        while j < len(toks):
            v = toks[j][1]
            if v == "(":
                depth += 1
            elif v == ")":
                depth -= 1
                if depth == 0:
                    return j + 1
            elif toks[j][0] == "id" and depth == 1 and toks[j - 1][1] in ("(", ","):
                self.declared.add(v)
            j += 1
        return j

    def _in_ternary(self, i: int) -> bool:
        """True when token i sits between `?` and `:` of a conditional expression."""
        toks = self.tokens
        depth = 0
        j = i - 1
        steps = 0
        while j >= 0 and steps < 200:
            v = toks[j][1]
            if v in (")", "]", "}"):
                depth += 1
            elif v in ("(", "[", "{"):
                if depth == 0:
                    return False
                depth -= 1
            elif depth == 0:
                if v == "?":
                    return True
                if v in (";", ",") or v == ":":
                    return False
            j -= 1
            steps += 1
        return False


def js_exports(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    names = set(re.findall(r"^function\s+([A-Za-z_]\w*)\s*\(", text, re.MULTILINE))
    names |= set(re.findall(r"^var\s+([A-Za-z_]\w*)\s*=", text, re.MULTILINE))
    return names


CONNECTIONS_RE = re.compile(r"^(\s*)Connections\s*\{\s*$")


def dead_config_handlers(path: Path, config_keys: set[str]) -> list[str]:
    """`function onFooChanged()` inside Connections targeting a KConfig map."""
    problems = []
    lines = path.read_text(encoding="utf-8").split("\n")
    i = 0
    while i < len(lines):
        m = CONNECTIONS_RE.match(lines[i])
        if not m:
            i += 1
            continue
        close = m.group(1) + "}"
        end = next((j for j in range(i + 1, len(lines)) if lines[j] == close), len(lines) - 1)
        block = lines[i:end + 1]
        if any(re.search(r"\btarget:\s*[\w.]*[cC]onfiguration\b", line) for line in block):
            for offset, line in enumerate(block):
                h = re.search(r"\bfunction on([A-Z]\w*)Changed\s*\(", line)
                if h and h.group(1) in config_keys:
                    problems.append(
                        f"{path.relative_to(ROOT)}:{i + offset + 1}: on{h.group(1)}Changed is never called "
                        f"for KConfig key '{h.group(1)}' (capitalized); watch it with a binding instead"
                    )
        i = end + 1
    return problems


def kcfg_keys(path: Path) -> set[str]:
    ns = "{http://www.kde.org/standards/kcfg/1.0}"
    return {entry.attrib["name"] for entry in ET.parse(path).getroot().iter(f"{ns}entry")}


def main() -> int:
    files = sorted(UI.glob("*.qml")) + sorted((ROOT / "plasmoid" / "contents" / "ui").glob("*.qml"))
    infos = {path: FileInfo(path) for path in files}
    exports = js_exports(JS)
    main_info = infos[UI / "main.qml"]
    root_members = main_info.members.get("", set()) | BASE_MEMBERS
    engine_members = main_info.members.get("engine", set())
    dbus_info = infos.get(UI / "DBusHelper.qml")
    dbus_members = (dbus_info.members.get("", set()) if dbus_info else main_info.members.get("dbusHelper", set()))
    problems: list[str] = []
    capitalized = {key for key in kcfg_keys(ROOT / "contents" / "config" / "main.xml") if key[:1].isupper()}
    for path in files:
        if path.parent == UI:
            problems += dead_config_handlers(path, capitalized)

    for path, info in infos.items():
        rel = path.relative_to(ROOT)
        wallpaper_side = path.parent == UI
        inherited = set(INHERITED["*"]) | INHERITED.get(path.name, set())
        for type_name in info.types_used:
            inherited |= INHERITED.get(type_name, set())
        known = (
            info.ids | info.declared | info.import_aliases | GLOBALS | inherited
            | QML_TYPES_AS_VALUES
        )
        seen: set[tuple[str, int]] = set()
        for name, line in info.uses:
            if name in known or name[:1].isupper():
                continue
            if (name, line) in seen:
                continue
            seen.add((name, line))
            problems.append(f"{rel}:{line}: '{name}' is not declared in this file")
        for owner, member, line in info.member_uses:
            if owner == "Wallhaven" and member not in exports:
                problems.append(f"{rel}:{line}: Wallhaven.{member} is not defined in wallhaven.js")
            if not wallpaper_side:
                continue
            if path.name == "config.qml":
                # The settings dialog guards every call with `if (liveWallpaper.x)`,
                # so a renamed/moved entry point would silently become a no-op.
                if owner == "liveWallpaper" and member not in root_members:
                    problems.append(f"{rel}:{line}: liveWallpaper.{member} is not a member of the wallpaper root")
                continue
            if owner == "host" or (owner == "root" and path.name == "main.qml"):
                if member not in root_members:
                    problems.append(f"{rel}:{line}: {owner}.{member} is not a member of the wallpaper root")
            elif owner == "engine" and member not in engine_members:
                problems.append(f"{rel}:{line}: engine.{member} is not a member of engine")
            elif owner in ("dbus", "dbusHelper") and member not in dbus_members:
                problems.append(f"{rel}:{line}: {owner}.{member} is not a member of DBusHelper")

    if problems:
        print("\n".join(sorted(set(problems))), file=sys.stderr)
        print(f"check-qml-refs: {len(set(problems))} problem(s)", file=sys.stderr)
        return 1
    print(f"QML reference check passed ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
