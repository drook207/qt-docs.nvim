"""Baut tests/fixtures/out/qtdemo.qch aus html/qtdemo und html/qtother/ als HTML-Modul mit .index."""
import os, shutil, sqlite3, struct, sys, zlib
here = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
qch = os.path.join(out, "qtdemo.qch")
if os.path.exists(qch):
    os.remove(qch)
c = sqlite3.connect(qch)
c.executescript("""
CREATE TABLE NamespaceTable (Id INTEGER PRIMARY KEY,Name TEXT );
CREATE TABLE FolderTable(Id INTEGER PRIMARY KEY, Name Text, NamespaceID INTEGER );
CREATE TABLE FileNameTable (FolderId INTEGER, Name TEXT, FileId INTEGER, Title TEXT );
CREATE TABLE FileDataTable (Id INTEGER PRIMARY KEY, Data BLOB );
CREATE TABLE IndexTable (Id INTEGER PRIMARY KEY, Name TEXT, Identifier TEXT, NamespaceId INTEGER, FileId INTEGER, Anchor TEXT );
CREATE TABLE MetaDataTable(Name Text, Value BLOB );
INSERT INTO NamespaceTable VALUES (1, 'org.qt-project.qtdemo.680');
INSERT INTO FolderTable VALUES (1, 'qtdemo', 1);
INSERT INTO MetaDataTable VALUES ('version', '6.8.0');
""")
html = open(os.path.join(here, "html/qtdemo/qdemo.html"), "rb").read()
c.execute("INSERT INTO FileDataTable VALUES (1, ?)", (struct.pack(">I", len(html)) + zlib.compress(html),))
c.execute("INSERT INTO FileNameTable VALUES (1, 'qdemo.html', 1, 'QDemo Class')")
for i, (name, ident, anchor) in enumerate([("QDemo", "QDemo", None), ("name", "QDemo::name", "name"),
                                            ("setName", "QDemo::setName", "setName"), ("A", "QDemo::A", "Enum-enum")]):
    c.execute("INSERT INTO IndexTable VALUES (?, ?, ?, 1, 1, ?)", (i + 1, name, ident, anchor))
c.commit(); c.close()
# HTML-Modul ohne .qch
dst = os.path.join(out, "qtother")
shutil.rmtree(dst, ignore_errors=True)
shutil.copytree(os.path.join(here, "html/qtother"), dst)
open(os.path.join(dst, "qtother.index"), "w").write("""<?xml version="1.0" encoding="UTF-8"?>
<INDEX url="https://doc.qt.io/qt" title="Qt Other" version="6.8.0" project="QtOther">
  <namespace name="" status="active">
    <class name="QBase" href="qbase.html" title="QBase Class" fulltitle="QBase">
      <function name="base" href="qbase.html#base"/>
    </class>
    <namespace name="QtOther" href="qtother-ns.html">
      <enum name="Mode" href="qtother-ns.html#Mode-enum"/>
    </namespace>
  </namespace>
</INDEX>
""")
print(out)
