#!/usr/bin/env python3
"""Helper for qt-docs.nvim (standard library only).

Commands:
  index <out.json> <path>...        Build keyword index from .qch files and
                                     HTML doc directories (*.index)
  render qch <file.qch> <vpath>     Render page from a .qch
  render file <path.html> <vpath>   Render page from an HTML file
  render stdin <vpath>              Render HTML from stdin (online docs)

Output of render: JSON {title, lines, anchors, vpath}
"""
import json
import os
import posixpath
import re
import sqlite3
import sys
import zlib
import xml.etree.ElementTree as ET
from html.parser import HTMLParser


# ---------------------------------------------------------------------------
# Index
# ---------------------------------------------------------------------------

def qch_connect(path):
    return sqlite3.connect("file:" + path + "?mode=ro", uri=True)


def index_qch(path, src_id, entries, files, bases):
    con = qch_connect(path)
    try:
        folders = {fid: name for fid, name in con.execute("SELECT Id, Name FROM FolderTable")}
        fmap = {}
        for folder_id, name, file_id, title in con.execute(
                "SELECT FolderId, Name, FileId, Title FROM FileNameTable"):
            if not name:
                continue
            vpath = posixpath.join(folders.get(folder_id, ""), name)
            fmap[file_id] = vpath
            files.append([vpath, src_id, title or ""])
        # Base classes from the class pages ("Inherits:" line)
        for file_id, title in con.execute("SELECT FileId, Title FROM FileNameTable"):
            m = re.match(r"^([\w:]+) (Class|Struct)\b", title or "")
            if not m:
                continue
            row = con.execute("SELECT Data FROM FileDataTable WHERE Id = ?", (file_id,)).fetchone()
            if not row:
                continue
            try:
                html = zlib.decompress(bytes(row[0])[4:]).decode("utf-8", "replace")
            except zlib.error:
                continue
            inh = re.search(r"Inherits:</td>\s*<td[^>]*>(.*?)</td>", html, re.S)
            if inh:
                found = re.findall(r">([\w:]+)</a>", inh.group(1))
                if found:
                    bases.setdefault(m.group(1), found)
        for name, ident, file_id, anchor in con.execute(
                "SELECT Name, Identifier, FileId, Anchor FROM IndexTable"):
            vpath = fmap.get(file_id)
            if not vpath:
                continue
            key = ident or name
            if not key:
                continue
            entries.append([key, vpath, anchor or ""])
        meta = dict(con.execute("SELECT Name, Value FROM MetaDataTable").fetchall())
        ns = con.execute("SELECT Name FROM NamespaceTable").fetchone()
        return {"type": "qch", "path": path, "version": str(meta.get("version", "")),
                "namespace": ns[0] if ns else ""}
    finally:
        con.close()


def index_xml(index_file, docroot, src_id, entries, files, bases):
    """Read a qdoc-*.index (from HTML doc packages)."""
    folder = posixpath.relpath(os.path.dirname(index_file), docroot).replace(os.sep, "/")
    if folder == ".":
        folder = ""
    try:
        tree = ET.parse(index_file)
    except ET.ParseError:
        return None
    root = tree.getroot()
    seen_files = set()

    def walk(node, scope):
        for child in node:
            name = child.get("name")
            href = child.get("href")
            child_scope = scope
            if name and child.tag in ("class", "struct", "union", "namespace", "enum", "typedef",
                                      "function", "variable", "property", "page", "qmlclass",
                                      "qmltype", "group", "module", "headerfile", "qmlproperty",
                                      "qmlmethod", "qmlsignal", "macro", "enumvalue"):
                if child.tag in ("page", "group", "module", "headerfile"):
                    key = child.get("title") or name
                else:
                    key = child.get("fullname") or ("::".join(scope + [name]) if scope else name)
                if href and not href.startswith("http"):
                    file_part, _, anchor = href.partition("#")
                    vpath = posixpath.normpath(posixpath.join(folder, file_part))
                    entries.append([key, vpath, anchor])
                    if vpath not in seen_files:
                        seen_files.add(vpath)
                        files.append([vpath, src_id, child.get("fulltitle") or child.get("title") or ""])
                    # Enum values (as in .qch: in the scope of the enum)
                    if child.tag == "enum":
                        for val in child.findall("value"):
                            vname = val.get("name")
                            if vname:
                                vkey = "::".join(scope + [vname]) if scope else vname
                                entries.append([vkey, vpath, anchor])
                if child.tag in ("class", "struct") and child.get("bases"):
                    full = child.get("fullname") or "::".join(scope + [name])
                    bl = [b.strip().split()[-1] for b in child.get("bases").split(",") if b.strip()]
                    bases.setdefault(full, bl)
                if child.tag in ("class", "struct", "union", "namespace") and name:
                    child_scope = scope + [name]
            walk(child, child_scope)

    walk(root, [])
    return {"type": "dir", "path": docroot, "version": root.get("version", "")}


def find_sources(paths):
    """Return [(kind, path, docroot)] – .qch preferred, otherwise *.index files."""
    result = []
    for p in paths:
        if os.path.isfile(p) and p.endswith(".qch"):
            result.append(("qch", p, None))
            continue
        if not os.path.isdir(p):
            continue
        qchs = sorted(f for f in os.listdir(p) if f.endswith(".qch"))
        qch_modules = set()
        for f in qchs:
            result.append(("qch", os.path.join(p, f), None))
            qch_modules.add(f[:-4])
        # HTML modules without .qch
        for d in sorted(os.listdir(p)):
            sub = os.path.join(p, d)
            if not os.path.isdir(sub) or d in qch_modules:
                continue
            for f in os.listdir(sub):
                if f.endswith(".index"):
                    result.append(("index", os.path.join(sub, f), p))
    return result


def cmd_index(out, paths):
    sources, entries, files, bases = [], [], [], {}
    for kind, path, docroot in find_sources(paths):
        try:
            if kind == "qch":
                src = index_qch(path, len(sources), entries, files, bases)
            else:
                src = index_xml(path, docroot, len(sources), entries, files, bases)
                if src:
                    src["index"] = path
        except Exception as e:  # skip broken file
            sys.stderr.write("%s: %s\n" % (path, e))
            src = None
        if src:
            sources.append(src)
    data = {"sources": sources, "entries": entries, "files": files, "bases": bases}
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, separators=(",", ":"))
    os.replace(tmp, out)
    print(json.dumps({"sources": len(sources), "entries": len(entries), "files": len(files)}))


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load_qch(path, vpath):
    con = qch_connect(path)
    try:
        folder, name = posixpath.split(vpath)
        row = con.execute(
            "SELECT d.Data FROM FileNameTable n JOIN FolderTable f ON n.FolderId = f.Id "
            "JOIN FileDataTable d ON d.Id = n.FileId WHERE n.Name = ? AND f.Name = ?",
            (name, folder)).fetchone()
        if not row:
            row = con.execute(
                "SELECT d.Data FROM FileNameTable n JOIN FileDataTable d ON d.Id = n.FileId "
                "WHERE n.Name = ?", (name,)).fetchone()
        if not row:
            raise FileNotFoundError(vpath)
        data = bytes(row[0])
        # qCompress: 4-byte length (big endian) + zlib
        try:
            raw = zlib.decompress(data[4:])
        except zlib.error:
            raw = data
        return raw.decode("utf-8", "replace")
    finally:
        con.close()


# ---------------------------------------------------------------------------
# HTML → Markdown
# ---------------------------------------------------------------------------

VOID = {"br", "img", "hr", "meta", "link", "input", "col", "area", "base", "wbr", "source", "embed", "param"}
SKIP_TAGS = {"head", "script", "style", "nav", "noscript", "svg", "button", "form", "template"}
SKIP_CLASSES = {"sidebar", "navigationbar", "footer", "toc", "breadcrumb", "breadcrumbs", "qt-sidebar",
                "sidebar-content", "context", "feedback", "cookie", "header-menu", "nav", "edit-link",
                "prev-next", "prevnext"}
SKIP_IDS = {"footer", "sidebar", "toc", "qtdocheader-menu", "feedback"}


def resolve_href(cur_vpath, href):
    if not href:
        return href
    if re.match(r"^[a-z]+:", href):
        # qthelp://org.qt-project.qtcore.642/qtcore/qstring.html
        m = re.match(r"^qthelp://[^/]+/(.*)$", href)
        if m:
            return m.group(1)
        return href
    if href.startswith("#"):
        return href
    file_part, sep, anchor = href.partition("#")
    if not file_part:
        return href
    base = posixpath.dirname(cur_vpath)
    path = posixpath.normpath(posixpath.join(base, file_part))
    if path == cur_vpath and anchor:
        return "#" + anchor
    return path + (sep + anchor if anchor else "")


class Converter(HTMLParser):
    def __init__(self, vpath, require_h1=True):
        super().__init__(convert_charrefs=True)
        self.vpath = vpath
        self.lines = []
        self.anchors = {}
        self.pending_anchors = []
        self.cur = []           # inline text of the current block
        self.stack = []         # [tag, skip]
        self.skip = 0
        self.pre = 0
        self.pre_lang = ""
        self.pre_buf = []
        self.lists = []         # ["ul"/"ol", counter]
        self.heading = 0
        self.links = []         # open <a>: href or None
        self.tables = []        # [{"rows": [[cells]], "cls": str}]
        self.cell = None
        self.title = ""
        self.in_title = False
        self.started = not require_h1
        self.quote = 0
        self.code = 0

    # -- Output -----------------------------------------------------------
    def emit(self, line):
        if self.pending_anchors and line.strip():
            for a in self.pending_anchors:
                self.anchors.setdefault(a, len(self.lines) + 1)
            self.pending_anchors = []
        self.lines.append(line)

    def blank(self):
        if self.lines and self.lines[-1] != "":
            self.lines.append("")

    def write(self, text):
        if self.cell is not None:
            self.cell.append(text)
        else:
            self.cur.append(text)

    def inline_text(self):
        s = "".join(self.cur)
        self.cur = []
        s = re.sub(r"[ \t\r\f\v]+", " ", s)
        return "\n".join(part.strip() for part in s.split("\n")).strip("\n")

    def flush(self, prefix="", blank_before=True):
        text = self.inline_text()
        if not text.strip():
            return
        if self.lists:
            depth = len(self.lists) - 1
            indent = "  " * depth
            first = True
            for part in text.split("\n"):
                if first:
                    self.emit(indent + prefix + part)
                    first = False
                else:
                    self.emit(indent + "  " + part)
            return
        if blank_before:
            self.blank()
        q = "> " * self.quote
        for part in text.split("\n"):
            self.emit(q + prefix + part)

    def add_anchor(self, attrs):
        for key in ("id", "name"):
            v = attrs.get(key)
            if v and self.started:
                self.pending_anchors.append(v)

    # -- Parser -----------------------------------------------------------
    def handle_starttag(self, tag, attrs_list):
        attrs = dict(attrs_list)
        if tag == "title":
            self.in_title = True
        void = tag in VOID
        cls = set((attrs.get("class") or "").split())
        skip_this = (tag in SKIP_TAGS or bool(cls & SKIP_CLASSES) or attrs.get("id") in SKIP_IDS
                     or attrs.get("role") in ("navigation", "banner", "contentinfo"))
        if not void:
            self.stack.append([tag, skip_this])
            if skip_this:
                self.skip += 1
        if self.skip:
            return
        if tag == "h1" and not self.started:
            self.started = True
        if not self.started:
            return
        self.add_anchor(attrs)

        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.flush()
            self.heading = int(tag[1])
        elif tag == "pre":
            self.flush()
            self.pre += 1
            lang = "cpp"
            for c in cls:
                if c in ("qml", "js", "javascript", "cpp", "cmake", "bash", "shell", "xml", "python", "json"):
                    lang = {"javascript": "js", "shell": "bash"}.get(c, c)
                elif c in ("text", "plaintext", "badcode"):
                    lang = "" if c != "badcode" else "cpp"
            self.pre_lang = lang
            self.pre_buf = []
        elif self.pre:
            return
        elif tag in ("p", "div", "dl", "dd", "dt", "blockquote", "section", "article", "main"):
            if self.cell is None:
                self.flush()
            if tag == "blockquote":
                self.quote += 1
            if tag == "dd":
                self.write("  ")
        elif tag == "br":
            self.write("\n")
        elif tag in ("ul", "ol"):
            if self.cell is None:
                self.flush(blank_before=not self.lists)
                if not self.lists:
                    self.blank()
            self.lists.append([tag, 0])
        elif tag == "li":
            if self.cell is None:
                self.flush_li()
            if self.lists:
                self.lists[-1][1] += 1
        elif tag in ("b", "strong"):
            if not self.heading:
                self.write("**")
        elif tag in ("i", "em", "var"):
            if not self.heading and not self.code:
                self.write("_")
        elif tag in ("code", "tt", "kbd"):
            if not self.heading:
                self.code += 1
                if self.code == 1:
                    self.write("`")
        elif tag == "a":
            href = attrs.get("href")
            if href and not self.heading and not self.code:
                self.links.append(resolve_href(self.vpath, href))
                self.write("[")
            else:
                self.links.append(None)
        elif tag == "table":
            if self.cell is None:
                self.flush()
            self.tables.append({"rows": [], "cls": cls, "header": []})
        elif tag == "tr":
            if self.tables:
                self.tables[-1]["rows"].append([])
        elif tag in ("td", "th"):
            if self.tables and self.cell is None:
                self.cell = []
                self.cell_is_th = tag == "th"
        elif tag == "hr":
            self.flush()
            self.blank()
            self.emit("---")
        elif tag == "img":
            alt = attrs.get("alt")
            if alt and alt.strip():
                self.write("[Image: " + alt.strip() + "]")

    def flush_li(self):
        if not self.lists:
            self.flush()
            return
        kind, n = self.lists[-1]
        prefix = "- " if kind == "ul" else "%d. " % max(n, 1)
        text = self.inline_text()
        if text.strip():
            depth = len(self.lists) - 1
            parts = text.split("\n")
            self.emit("  " * depth + prefix + parts[0])
            for part in parts[1:]:
                self.emit("  " * depth + " " * len(prefix) + part)

    def handle_endtag(self, tag):
        # find the matching start tag (fault-tolerant)
        idx = None
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i][0] == tag:
                idx = i
                break
        if idx is None:
            return
        was_skipping = self.skip > 0
        for t, sk in self.stack[idx:]:
            if sk:
                self.skip -= 1
        del self.stack[idx:]
        if tag == "title":
            self.in_title = False
        if was_skipping or not self.started:
            return
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6") and self.heading:
            level = self.heading
            self.heading = 0
            text = self.inline_text().replace("\n", " ").strip()
            if text:
                self.blank()
                self.emit("#" * level + " " + text)
                self.blank()
        elif tag == "pre" and self.pre:
            self.pre -= 1
            if self.pre == 0:
                text = "".join(self.pre_buf)
                text = text.strip("\n")
                lines = text.split("\n")
                # remove common indentation
                ind = min((len(l) - len(l.lstrip(" ")) for l in lines if l.strip()), default=0)
                self.blank()
                if self.lists:
                    pad = "  " * len(self.lists)
                else:
                    pad = ""
                self.emit(pad + "```" + self.pre_lang)
                for l in lines:
                    self.emit(pad + l[ind:].rstrip())
                self.emit(pad + "```")
                self.blank()
        elif self.pre:
            return
        elif tag in ("p", "div", "dl", "dd", "dt", "section", "article", "main"):
            if self.cell is None:
                self.flush()
                if tag == "p":
                    self.blank()
        elif tag == "blockquote":
            self.flush()
            self.quote = max(0, self.quote - 1)
        elif tag in ("ul", "ol"):
            if self.cell is None:
                self.flush_li()
            if self.lists:
                self.lists.pop()
            if not self.lists:
                self.blank()
        elif tag == "li":
            if self.cell is None:
                self.flush_li()
            else:
                self.write("\x00")
        elif tag in ("b", "strong"):
            if not self.heading:
                self.write("**")
        elif tag in ("i", "em", "var"):
            if not self.heading and not self.code:
                self.write("_")
        elif tag in ("code", "tt", "kbd"):
            if not self.heading and self.code:
                self.code -= 1
                if self.code == 0:
                    self.write("`")
        elif tag == "a":
            href = self.links.pop() if self.links else None
            if href:
                self.write("](" + href.replace(" ", "%20").replace(")", "%29") + ")")
        elif tag in ("td", "th"):
            if self.cell is not None and self.tables:
                text = "".join(self.cell)
                text = re.sub(r"[ \t\r\n\f\v]+", " ", text).strip()
                text = text.replace("|", "\\|")
                rows = self.tables[-1]["rows"]
                if not rows:
                    rows.append([])
                rows[-1].append(text)
                if getattr(self, "cell_is_th", False):
                    self.tables[-1]["header"] = rows[-1]
                self.cell = None
        elif tag == "table":
            if self.tables:
                self.render_table(self.tables.pop())

    def render_table(self, t):
        rows = [r for r in t["rows"] if any(c.strip() for c in r)]
        if not rows:
            return
        cls = t["cls"]
        width = max(len(r) for r in rows)
        self.blank()
        has_items = any("\x00" in c for r in rows for c in r)
        if has_items:
            # Lists in table cells (properties, "-members" pages): one entry per line
            for r in rows:
                for c in r:
                    for item in c.split("\x00"):
                        item = item.strip(" ;")
                        if item:
                            self.emit("- " + item)
        elif "alignedsummary" in cls or "propsummary" in cls or width <= 2 and not t["header"]:
            # Summaries: "type  signature" as a list
            for r in rows:
                left = r[0].strip() if r else ""
                right = " ".join(c.strip() for c in r[1:]).strip()
                if right:
                    if left.endswith(":"):
                        self.emit("- **" + left + "** " + right)
                    elif left and re.search(r"[\[\]*`\\]", left):
                        self.emit("- " + left + " " + right)
                    elif left:
                        self.emit("- `" + left + "` " + right)
                    else:
                        self.emit("- " + right)
                elif left:
                    self.emit("- " + left)
        else:
            header = t["header"] if t["header"] and t["header"] is rows[0] else None
            if header is None:
                header = rows[0]
                body = rows[1:]
            else:
                body = rows[1:]
            rows = [[c.replace("\x00", " ") for c in r] for r in rows]
            header = [c.replace("\x00", " ") for c in header]
            body = rows[1:]
            pad = lambda r: r + [""] * (width - len(r))
            self.emit("| " + " | ".join(pad(header)) + " |")
            self.emit("|" + "---|" * width)
            for r in body:
                self.emit("| " + " | ".join(pad(r)) + " |")
        self.blank()

    def handle_data(self, data):
        if self.in_title:
            self.title += data
        if self.skip or not self.started:
            return
        if self.pre:
            self.pre_buf.append(data)
            return
        if self.cell is None and not data.strip() and not self.cur:
            return
        if not self.code:
            # escape only real pitfalls: "char **argv", "operator[]()"
            data = data.replace("**", "\\*\\*").replace("[]", "\\[\\]")
        self.write(data.replace("\n", " "))

    def result(self):
        self.flush()
        while self.lines and self.lines[-1] == "":
            self.lines.pop()
        while self.lines and self.lines[0] == "":
            self.lines.pop(0)
        # Collapse multiple blank lines (except in code)
        out, anchors_shift = [], {}
        in_code = False
        mapping = {}
        for i, l in enumerate(self.lines, 1):
            if l.lstrip().startswith("```"):
                in_code = not in_code
            if not in_code and l == "" and out and out[-1] == "":
                mapping[i] = len(out)
                continue
            out.append(l)
            mapping[i] = len(out)
        anchors = {k: mapping.get(v, v) for k, v in self.anchors.items()}
        return out, anchors


def render(html, vpath):
    conv = Converter(vpath)
    conv.feed(html)
    conv.close()
    lines, anchors = conv.result()
    if not lines:  # no <h1>: take everything
        conv = Converter(vpath, require_h1=False)
        conv.feed(html)
        conv.close()
        lines, anchors = conv.result()
    title = re.sub(r"\s+", " ", conv.title).strip()
    return {"title": title, "lines": lines, "anchors": anchors, "vpath": vpath}


def cmd_render(kind, args):
    if kind == "qch":
        html = load_qch(args[0], args[1])
        vpath = args[1]
    elif kind == "file":
        with open(args[0], encoding="utf-8", errors="replace") as fh:
            html = fh.read()
        vpath = args[1]
    else:
        html = sys.stdin.buffer.read().decode("utf-8", "replace")
        vpath = args[0]
    sys.stdout.write(json.dumps(render(html, vpath)))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    if cmd == "index":
        cmd_index(sys.argv[2], sys.argv[3:])
    elif cmd == "render":
        cmd_render(sys.argv[2], sys.argv[3:])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
