"""Fetch today's Kerala gold rate per gram (22K and 24K) and write gold.json.

Tries local Kerala retail rate pages first, then falls back to an estimate
from the international spot price. Every value is sanity-checked.
Run by .github/workflows/gold.yml a few times a day.
"""
import json, re, sys, time, urllib.request
from datetime import datetime, timezone, timedelta

UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36",
      "Accept-Language": "en-IN,en;q=0.9"}
LO, HI = 3000, 60000  # plausible INR per gram range
IST = timezone(timedelta(hours=5, minutes=30))


def get(url, timeout=25):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "ignore")


def num(s):
    try:
        return float(s.replace(",", ""))
    except Exception:
        return None


def ok(v):
    return v is not None and LO <= v <= HI


def text_of(html):
    t = re.sub(r"<script.*?</script>|<style.*?</style>", " ", html, flags=re.S | re.I)
    t = re.sub(r"<[^>]+>", " ", t)
    t = t.replace("&#8377;", "₹").replace("&nbsp;", " ").replace("Rs.", "₹").replace("Rs", "₹")
    return re.sub(r"\s+", " ", t)


def per_gram_after(t, label_re):
    """First ₹ amount per 1 gram that follows a 22K/24K label, before the next carat label."""
    other = re.compile(r"\b(?:14|18|20|22|23|24)\s*(?:K|KT|Carat|Karat|ct)\b", re.I)
    for m in re.finditer(label_re, t, flags=re.I):
        window = t[m.end(): m.end() + 600]
        nxt = other.search(window)
        if nxt:
            window = window[: nxt.start()]
        g = re.search(r"\b1\s*(?:g|gm|gram)?s?\b[^₹\d]{0,40}₹\s*([\d,]+(?:\.\d+)?)", window, flags=re.I)
        if g and ok(num(g.group(1))):
            return num(g.group(1))
        p = re.search(r"₹\s*([\d,]+(?:\.\d+)?)\s*(?:/|per)\s*(?:g|gm|gram)\b", window, flags=re.I)
        if p and ok(num(p.group(1))):
            return num(p.group(1))
    return None


def from_page(url):
    t = text_of(get(url))
    return parse_rates(t)


def parse_rates(t):
    # Column layout: "22 Carat 24 Carat ... 1 g ₹a ₹b"
    col = re.search(r"22\s*(?:K|KT|Carat|Karat|ct)\b[^₹]{0,30}?24\s*(?:K|KT|Carat|Karat|ct)\b"
                    r"[^₹]{0,80}?\b1\s*(?:g|gm|gram)?s?\b[^₹\d]{0,20}₹\s*([\d,]+(?:\.\d+)?)[^₹]{0,30}₹\s*([\d,]+(?:\.\d+)?)",
                    t, flags=re.I)
    if col and ok(num(col.group(1))) and ok(num(col.group(2))):
        r22, r24 = num(col.group(1)), num(col.group(2))
    else:
        r22 = per_gram_after(t, r"22\s*(?:K|KT|Carat|Karat|ct)\b")
        r24 = per_gram_after(t, r"24\s*(?:K|KT|Carat|Karat|ct)\b")
    # 24K should be about 1.09x the 22K rate; otherwise the page was misread.
    if ok(r22) and ok(r24) and not (1.03 <= r24 / r22 <= 1.17):
        print("inconsistent 22K/24K, ignoring page values:", r22, r24)
        return None, None
    return r22, r24


def from_international():
    """Estimate Indian rate from spot gold (USD/oz) x USD/INR + import duty."""
    usd_oz = None
    for url, path in [("https://api.gold-api.com/price/XAU", ("price",)),
                      ("https://data-asg.goldprice.org/dbXRates/USD", ("items", 0, "xauPrice"))]:
        try:
            d = json.loads(get(url))
            for k in path:
                d = d[k]
            usd_oz = float(d)
            break
        except Exception as e:
            print("spot source failed:", url, e)
    inr = None
    for url, path in [("https://open.er-api.com/v6/latest/USD", ("rates", "INR")),
                      ("https://api.frankfurter.app/latest?from=USD&to=INR", ("rates", "INR"))]:
        try:
            d = json.loads(get(url))
            for k in path:
                d = d[k]
            inr = float(d)
            break
        except Exception as e:
            print("fx source failed:", url, e)
    if not usd_oz or not inr:
        return None, None
    r24 = usd_oz / 31.1035 * inr * 1.06  # ~6% import duty, before GST
    return round(r24 * 0.916), round(r24)


def main(out):
    result = None
    for name, url in [
        ("goodreturns.in (Kerala)", "https://www.goodreturns.in/gold-rates/kerala.html"),
        ("goldrate.com (Kerala)", "https://goldrate.com/gold-rate-today/kerala"),
        ("bankbazaar.com (Kerala)", "https://www.bankbazaar.com/gold-rate-kerala.html"),
    ]:
        try:
            r22, r24 = from_page(url)
            print(name, "->", r22, r24)
            if ok(r22) or ok(r24):
                if not ok(r22):
                    r22 = round(r24 * 0.916)
                if not ok(r24):
                    r24 = round(r22 / 0.916)
                result = {"rate22": r22, "rate24": r24, "source": name, "approx": False}
                break
        except Exception as e:
            print(name, "failed:", e)
    if result is None:
        r22, r24 = from_international()
        print("international estimate ->", r22, r24)
        if ok(r22):
            result = {"rate22": r22, "rate24": r24, "source": "international spot price (estimate)",
                      "approx": True}
    if result is None:
        print("No gold rate source worked; keeping the previous file.")
        sys.exit(1)
    result["at"] = datetime.now(IST).isoformat(timespec="minutes")
    json.dump(result, open(out, "w"), indent=2)
    print(json.dumps(result))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "gold.json")
