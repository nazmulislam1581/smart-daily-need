"""GitHub Actions-এ চলে: হাদিস (HadeethEnc, বাংলা) ও কুরআনের আয়াত (alquran.cloud)
ডাউনলোড করে assets/data/hadith.json ও assets/data/quran_verses.json তৈরি করে।"""
import json, pathlib, sys, time, urllib.request, urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
BN_DIGITS = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")

SURAH_BN = ["আল-ফাতিহা","আল-বাকারা","আলে ইমরান","আন-নিসা","আল-মায়িদা","আল-আনআম","আল-আরাফ","আল-আনফাল","আত-তাওবা","ইউনুস",
"হুদ","ইউসুফ","আর-রাদ","ইবরাহিম","আল-হিজর","আন-নাহল","বনি ইসরাইল","আল-কাহফ","মারইয়াম","ত্বা-হা",
"আল-আম্বিয়া","আল-হজ","আল-মুমিনুন","আন-নূর","আল-ফুরকান","আশ-শুআরা","আন-নামল","আল-কাসাস","আল-আনকাবুত","আর-রুম",
"লুকমান","আস-সাজদা","আল-আহযাব","সাবা","ফাতির","ইয়াসিন","আস-সাফফাত","সাদ","আয-যুমার","আল-মুমিন",
"হা-মিম আস-সাজদা","আশ-শুরা","আয-যুখরুফ","আদ-দুখান","আল-জাসিয়া","আল-আহকাফ","মুহাম্মদ","আল-ফাতহ","আল-হুজুরাত","কাফ",
"আয-যারিয়াত","আত-তুর","আন-নাজম","আল-কামার","আর-রহমান","আল-ওয়াকিয়া","আল-হাদিদ","আল-মুজাদালা","আল-হাশর","আল-মুমতাহিনা",
"আস-সাফ","আল-জুমুআ","আল-মুনাফিকুন","আত-তাগাবুন","আত-তালাক","আত-তাহরিম","আল-মুলক","আল-কলম","আল-হাক্কা","আল-মাআরিজ",
"নুহ","আল-জিন","আল-মুযযাম্মিল","আল-মুদ্দাসসির","আল-কিয়ামা","আদ-দাহর","আল-মুরসালাত","আন-নাবা","আন-নাযিআত","আবাসা",
"আত-তাকভির","আল-ইনফিতার","আল-মুতাফফিফিন","আল-ইনশিকাক","আল-বুরুজ","আত-তারিক","আল-আলা","আল-গাশিয়া","আল-ফাজর","আল-বালাদ",
"আশ-শামস","আল-লাইল","আদ-দুহা","আশ-শারহ","আত-তিন","আল-আলাক","আল-কদর","আল-বাইয়্যিনা","আয-যিলযাল","আল-আদিয়াত",
"আল-কারিআ","আত-তাকাসুর","আল-আসর","আল-হুমাযা","আল-ফিল","কুরাইশ","আল-মাউন","আল-কাওসার","আল-কাফিরুন","আন-নাসর",
"আল-লাহাব","আল-ইখলাস","আল-ফালাক","আন-নাস"]
assert len(SURAH_BN) == 114


def get_json(url, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "SmartDailyNeed/1.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:  # noqa
            if i == tries - 1:
                raise
            time.sleep(2 + i * 2)


def build_quran():
    refs = []
    for line in (ROOT / "tools/quran_refs.txt").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        refs.append(line)
    seen, out = set(), []
    for ref in refs:
        if ref in seen:
            continue
        seen.add(ref)
        s, a = ref.split(":")
        if "-" in a:
            a1, a2 = map(int, a.split("-"))
        else:
            a1 = a2 = int(a)
        ar, bn = [], []
        try:
            for n in range(a1, a2 + 1):
                j = get_json(f"https://api.alquran.cloud/v1/ayah/{s}:{n}/editions/quran-uthmani,bn.bengali")
                ar.append(j["data"][0]["text"])
                bn.append(j["data"][1]["text"])
                time.sleep(0.15)
        except Exception as e:
            print("skip quran", ref, e)
            continue
        ayat = f"{a1}" if a1 == a2 else f"{a1}-{a2}"
        label = f"সূরা {SURAH_BN[int(s) - 1]} ({s}:{ayat})".translate(BN_DIGITS)
        out.append({"refs": [ref], "label": label, "arabic": " ۝ ".join(ar), "bangla": " ".join(bn)})
    print("quran entries:", len(out))
    if len(out) < 300:
        sys.exit("too few quran entries")
    (ROOT / "assets/data/quran_verses.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")


def build_hadith(target=420):
    base = "https://hadeethenc.com/api/v1"
    cats = get_json(f"{base}/categories/list/?language=bn")
    ids = []
    for c in cats:
        page = 1
        while True:
            q = urllib.parse.urlencode({"language": "bn", "category_id": c["id"], "page": page, "per_page": 100})
            try:
                j = get_json(f"{base}/hadeeths/list/?{q}")
            except Exception as e:
                print("list fail", c["id"], e)
                break
            data = j.get("data", [])
            for h in data:
                if h["id"] not in ids:
                    ids.append(h["id"])
            meta = j.get("meta", {})
            if page >= int(meta.get("last_page", 1)) or not data:
                break
            page += 1
    print("hadith ids:", len(ids))
    out = []
    for hid in ids:
        if len(out) >= target:
            break
        try:
            h = get_json(f"{base}/hadeeths/one/?language=bn&id={hid}")
        except Exception as e:
            print("skip hadith", hid, e)
            continue
        text = (h.get("hadeeth") or "").strip()
        if not text or len(text) > 700:
            continue
        grade = (h.get("grade") or "").strip()
        attr = (h.get("attribution") or "").strip()
        ref = attr + (f" • {grade}" if grade else "")
        out.append({"text": text, "ref": ref or "HadeethEnc.com"})
        time.sleep(0.1)
    print("hadith entries:", len(out))
    if len(out) < 365:
        sys.exit("too few hadith entries")
    (ROOT / "assets/data/hadith.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    what = sys.argv[1:] or ["quran", "hadith"]
    if "quran" in what:
        build_quran()
    if "hadith" in what:
        build_hadith()
