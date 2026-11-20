"""GitHub Actions-এ প্রতি ৩০ মিনিটে চলে: প্রথম আলোর RSS থেকে ছবিসহ ১০টি খবর
content/news.json-এ লেখে (ওয়েবসাইট সংস্করণ ও বিকল্প উৎস হিসেবে ব্যবহৃত)।"""
import json, pathlib, re, urllib.request, email.utils
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
MEDIA = "{http://search.yahoo.com/mrss/}"
FEEDS = [("https://www.prothomalo.com/stories.rss", "প্রথম আলো"),
         ("https://news.google.com/rss?hl=bn&gl=BD&ceid=BD:bn", "")]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 AjkerDin/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def strip(html):
    t = re.sub(r"<[^>]*>", " ", html or "")
    return re.sub(r"\s+", " ", t.replace("&nbsp;", " ")).strip()


def parse(url, source):
    root = ET.fromstring(get(url))
    out = []
    for it in root.iter("item"):
        title = (it.findtext("title") or "").strip()
        if not source and " - " in title:
            title = title.rsplit(" - ", 1)[0]
        img = ""
        mc = it.find(MEDIA + "content")
        if mc is not None and mc.get("url"):
            img = mc.get("url").split("?")[0] + "?w=720"
        elif it.find(MEDIA + "thumbnail") is not None:
            img = it.find(MEDIA + "thumbnail").get("url", "")
        summary = "" if not source else strip(it.findtext("description"))
        if len(summary) > 160:
            summary = summary[:157] + "..."
        pub = it.findtext("pubDate")
        iso = None
        if pub:
            try:
                iso = email.utils.parsedate_to_datetime(pub).isoformat()
            except Exception:
                pass
        out.append({"t": title, "s": it.findtext("source") or source, "l": (it.findtext("link") or "").strip(),
                    "i": img, "d": summary, "p": iso})
        if len(out) == 10:
            break
    return out


items = []
for url, src in FEEDS:
    try:
        items = parse(url, src)
        if items:
            break
    except Exception as e:
        print("feed failed", url, e)
if items:
    (ROOT / "content/news.json").write_text(json.dumps({"items": items}, ensure_ascii=False, indent=1), encoding="utf-8")
    print("news:", len(items))
