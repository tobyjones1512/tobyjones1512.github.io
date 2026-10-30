#!/usr/bin/env python3
"""Builds the Food Hygiene app's regional rating snapshots for feeds the app can't query live
(address-only feeds that need geocoding). Regions whose feeds have coordinates are queried live in the app.

Builds the regional rating snapshots (food-hygiene/data/*.json + manifest.json).

Each source is an official open-data feed from a US state, county or city health department. The
build keeps the most recent inspection per establishment, geocodes addresses with the US Census
batch geocoder where the feed has no coordinates, and writes one small JSON file per region.
Standard library only. Run from the repo root:  python3 tools/food-hygiene/build.py [region-id ...]
"""
import csv, datetime, hashlib, io, json, math, os, sys, time, urllib.parse, urllib.request, uuid

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "..", "..", "food-hygiene", "data")
CACHE = os.path.join(ROOT, "geocode-cache.json")
TODAY = datetime.date.today().isoformat()
UA = {"User-Agent": "FoodHygieneRatingsApp-DataBuild/1.0 (hello@thecaffeinemediacompany.com)"}


def http(url, data=None, headers=None, timeout=120, tries=4):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers={**UA, **(headers or {})})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:
            if attempt == tries - 1:
                raise
            time.sleep(3 * (attempt + 1))


def get_json(base, params):
    return json.loads(http(base + "?" + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)))


def socrata(domain, dataset, select, where=None, order=None, page=50000):
    rows, offset = [], 0
    while True:
        params = {"$select": select, "$limit": page, "$offset": offset, "$order": order or ":id"}
        if where:
            params["$where"] = where
        chunk = get_json(f"https://{domain}/resource/{dataset}.json", params)
        rows += chunk
        if len(chunk) < page:
            return rows
        offset += page


def arcgis(url, where="1=1", fields="*", geometry=False):
    rows, offset = [], 0
    while True:
        d = get_json(url + "/query", {"where": where, "outFields": fields, "outSR": 4326, "f": "json", "returnGeometry": str(geometry).lower(),
                                      "resultOffset": offset, "resultRecordCount": 1000})
        feats = d.get("features", [])
        rows += feats
        if not feats or not d.get("exceededTransferLimit"):
            return rows
        offset += len(feats)


def clean(s):
    s = (s or "").strip().strip('"').strip()
    return " ".join(s.split())


def title(s):
    s = clean(s)
    if any(c.islower() for c in s):
        return s
    out, prev = [], " "
    for c in s:
        out.append(c.upper() if not (prev.isalnum() or prev in "'’") else c.lower())
        prev = c
    return "".join(out)


def sid(*parts):
    return hashlib.sha1("|".join(parts).encode()).hexdigest()[:12]


# ---------------------------------------------------------------- geocoding (US Census batch)

def load_cache():
    try:
        return json.load(open(CACHE))
    except Exception:
        return {}


def geocode(records, cache):
    """records need street/city/state/zip; fills lat/lon from cache or the Census batch geocoder."""
    def key(r):
        return "|".join(clean(r.get(k)).upper() for k in ("street", "city", "state", "zip"))
    todo = sorted({key(r) for r in records if key(r) not in cache})
    print(f"  geocoding {len(todo)} new addresses ({len(records) - len(todo)} cached or duplicate)")
    for start in range(0, len(todo), 8000):
        batch = todo[start:start + 8000]
        buf = io.StringIO()
        w = csv.writer(buf)
        for i, k in enumerate(batch):
            street, city, state, zipc = k.split("|")
            w.writerow([i, street, city, state, zipc[:5]])
        boundary = uuid.uuid4().hex
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="benchmark"\r\n\r\nPublic_AR_Current\r\n'
                f'--{boundary}\r\nContent-Disposition: form-data; name="addressFile"; filename="a.csv"\r\nContent-Type: text/csv\r\n\r\n'
                f'{buf.getvalue()}\r\n--{boundary}--\r\n').encode()
        out = http("https://geocoding.geo.census.gov/geocoder/locations/addressbatch", data=body, timeout=900, tries=3,
                   headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}).decode("utf-8", "replace")
        matched = 0
        for row in csv.reader(io.StringIO(out)):
            if len(row) >= 6 and row[2] == "Match" and row[5]:
                lon, lat = row[5].split(",")
                cache[batch[int(row[0])]] = [round(float(lat), 5), round(float(lon), 5)]
                matched += 1
            elif row:
                cache[batch[int(row[0])]] = None
        print(f"    batch {start // 8000 + 1}: {matched}/{len(batch)} matched")
        json.dump(cache, open(CACHE, "w"))
    kept = []
    for r in records:
        hit = cache.get(key(r))
        if hit:
            r["lat"], r["lon"] = hit
            kept.append(r)
    print(f"  {len(kept)}/{len(records)} records have coordinates")
    return kept


# ---------------------------------------------------------------- sources
# Rating legends: key, short badge text, label, tier (good/fair/poor/neutral/pending), sort (higher is better).

def R(key, short, label, tier, sort):
    return {"key": key, "short": short, "label": label, "tier": tier, "sort": sort}


GRADES = [R("A", "A", "Grade A", "good", 90), R("B", "B", "Grade B", "fair", 80), R("C", "C", "Grade C", "poor", 70)]


def latest_per(rows, keyf, datef):
    best = {}
    for r in rows:
        k = keyf(r)
        if k and (k not in best or datef(r) > datef(best[k])):
            best[k] = r
    return list(best.values())


def src_king():
    rows = socrata("data.kingcounty.gov", "r878-4sxa", "business_id,name,address,city,zip_code,inspection_date,grade,classification",
                   where="grade IS NOT NULL")
    m = {"excellent": "1", "good": "2", "okay": "3", "needs to improve": "4"}
    rows = [r for r in rows if r.get("grade", "").lower() in m and r.get("business_id")]
    out = []
    for r in latest_per(rows, lambda r: r["business_id"], lambda r: r["inspection_date"]):
        out.append({"id": r["business_id"], "name": title(r["name"]), "street": clean(r.get("address")), "city": clean(r.get("city")), "state": "WA",
                    "zip": clean(r.get("zip_code")), "rk": m[r["grade"].lower()], "date": r["inspection_date"][:10], "type": clean(r.get("classification"))})
    return out


def src_marin():
    rows = socrata("data.marincounty.gov", "73zb-z5me", "business_name,license_number,inspection_date,placard,business_city,business_postal_code,formatted_address",
                   where="placard in ('GREEN','YELLOW','RED')")
    out = []
    for r in latest_per(rows, lambda r: r.get("license_number"), lambda r: r["inspection_date"]):
        addr = clean(r.get("formatted_address"))
        street = addr.split(",")[0].strip()
        out.append({"id": r["license_number"], "name": title(r["business_name"]), "street": street, "city": title(r.get("business_city")), "state": "CA",
                    "zip": clean(r.get("business_postal_code")), "rk": r["placard"], "date": r["inspection_date"][:10]})
    return out


def src_louisville():
    base = "https://services1.arcgis.com/79kfd2K6fskCAkyg/arcgis/rest/services/FoodServiceData/FeatureServer/0"
    rows = [f["attributes"] for f in arcgis(base, where="Grade IS NOT NULL AND InspectionDate IS NOT NULL")]
    rows = [r for r in rows if clean(r.get("Grade")).upper() in ("A", "B", "C")]
    out = []
    for r in latest_per(rows, lambda r: r.get("EstablishmentID"), lambda r: r["InspectionDate"]):
        score = r.get("score")
        out.append({"id": str(r["EstablishmentID"]), "name": title(r.get("EstablishmentName")), "street": clean(r.get("Address")),
                    "city": title(r.get("City")) or "Louisville", "state": "KY", "zip": clean(str(r.get("Zip") or ""))[:5],
                    "rk": clean(r["Grade"]).upper(), "date": r["InspectionDate"][:10],
                    "detail": f"score {score:g}" if score is not None else None, "type": title(r.get("TypeDescription"))})
    return out


REGIONS = [
    dict(id="king-wa", name="King County, Washington", country="United States", fetch=src_king, geocode=True,
         scheme="King County Food Safety Rating", summary="Rated 1 (excellent) to 4 (needs to improve) from recent inspections, by Public Health - Seattle & King County.",
         authority="Public Health - Seattle & King County", source="King County Open Data",
         ratings=[R("1", "1", "Excellent", "good", 4), R("2", "2", "Good", "good", 3), R("3", "3", "Okay", "fair", 2), R("4", "4", "Needs to Improve", "poor", 1)]),
    dict(id="marin-ca", name="Marin County, California", country="United States", fetch=src_marin, geocode=True,
         scheme="Marin County Food Placards", summary="A green (pass), yellow (conditional pass) or red (closed) placard from Marin County Environmental Health Services.",
         authority="Marin County Environmental Health Services", source="Marin County Open Data",
         ratings=[R("GREEN", "✓", "Green placard – Pass", "good", 80), R("YELLOW", "!", "Yellow placard – Conditional Pass", "fair", 50), R("RED", "✗", "Red placard – Closed", "poor", 10)]),
    dict(id="louisville-ky", name="Louisville, Kentucky", country="United States", fetch=src_louisville, geocode=True,
         scheme="Louisville Food Service Grades", summary="Grade A (90-100), B (80-89) or C (70-79) from a score out of 100, from Louisville Metro Public Health and Wellness.",
         authority="Louisville Metro Public Health and Wellness", source="Louisville Metro Open Data", ratings=GRADES),
]


def coverage(points, cell=0.05, min_count=8, radius_km=6.0):
    """Circles covering the busy parts of a region, so the app can tell where a user is without downloading it."""
    cells = {}
    for lat, lon in points:
        k = (math.floor(lat / cell), math.floor(lon / (cell / max(math.cos(math.radians(lat)), 0.2))))
        c = cells.setdefault(k, [0, 0.0, 0.0])
        c[0] += 1; c[1] += lat; c[2] += lon
    return [{"lat": round(s1 / n, 4), "lon": round(s2 / n, 4), "km": radius_km} for n, s1, s2 in cells.values() if n >= min_count]


def main():
    only = set(sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    cache = load_cache()
    manifest_path = os.path.join(OUT, "manifest.json")
    old = {}
    try:
        old = {r["id"]: r for r in json.load(open(manifest_path))["regions"]}
    except Exception:
        pass
    regions = []
    for reg in REGIONS:
        if only and reg["id"] not in only:
            if reg["id"] in old:
                regions.append(old[reg["id"]])
            continue
        print(f"== {reg['id']}")
        try:
            recs = reg["fetch"]()
            print(f"  {len(recs)} establishments")
            if reg.get("geocode"):
                recs = geocode(recs, cache)
            if len(recs) < 200:
                raise RuntimeError("too few records")
        except Exception as e:
            print(f"  FAILED: {e}; keeping previous snapshot")
            if reg["id"] in old:
                regions.append(old[reg["id"]])
            continue
        legend = {r["key"] for r in reg["ratings"]}
        recs = [r for r in recs if r["rk"] in legend and r.get("name")]
        rtype = reg.get("type", "Restaurant")
        rows = [[r["id"], r["name"], r["address"] if "address" in r else ", ".join(x for x in (title(r["street"]), title(r["city"]), r["state"], r["zip"]) if x),
                 r["lat"], r["lon"], r["rk"], r["date"], r.get("detail") or "", r.get("type") or rtype] for r in recs]
        fname = f"{reg['id']}.json"
        json.dump({"v": 1, "id": reg["id"], "generated": TODAY, "records": rows}, open(os.path.join(OUT, fname), "w"), separators=(",", ":"), ensure_ascii=False)
        regions.append({"id": reg["id"], "name": reg["name"], "country": reg["country"], "schemeName": reg["scheme"], "schemeSummary": reg["summary"],
                        "authority": reg["authority"], "source": reg["source"], "file": fname, "count": len(rows), "updated": TODAY,
                        "areas": coverage([(r[3], r[4]) for r in rows]), "ratings": reg["ratings"]})
        print(f"  wrote {fname}: {len(rows)} rows, {os.path.getsize(os.path.join(OUT, fname)) // 1024} KB, {len(regions[-1]['areas'])} coverage circles")
    json.dump({"v": 1, "generated": TODAY, "regions": regions}, open(manifest_path, "w"), separators=(",", ":"), ensure_ascii=False)


if __name__ == "__main__":
    main()
