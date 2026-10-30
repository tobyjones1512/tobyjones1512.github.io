#!/usr/bin/env python3
"""Builds the Food Hygiene app's regional rating snapshots (food-hygiene/data/*.json + manifest.json).

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


def src_ny_state():
    rows = socrata("data.ny.gov", "d6dy-3h7r", "trade_name,street,city,zipcode,inspection_grade,inspection_date,georeference",
                   where="georeference IS NOT NULL AND inspection_grade IS NOT NULL")
    rows = [r for r in rows if r.get("inspection_grade") in ("A", "B", "C") and r.get("georeference") and r.get("trade_name")]
    out = []
    for r in latest_per(rows, lambda r: sid(r["trade_name"], r.get("street", ""), r.get("zipcode", "")), lambda r: r["inspection_date"]):
        lon, lat = r["georeference"]["coordinates"]
        out.append({"id": sid(r["trade_name"], r.get("street", ""), r.get("zipcode", "")), "name": title(r["trade_name"]),
                    "address": ", ".join(p for p in (title(r.get("street")), title(r.get("city")), "NY", r.get("zipcode", "")) if p),
                    "lat": round(float(lat), 5), "lon": round(float(lon), 5), "rk": r["inspection_grade"], "date": r["inspection_date"][:10]})
    return out


def src_santa_clara():
    biz = {b["business_id"]: b for b in socrata("data.sccgov.org", "vuw7-jmjk", "business_id,name,address,city,state,postal_code,latitude,longitude")}
    ins = socrata("data.sccgov.org", "2u2d-8jej", "business_id,date,result", where="result in ('G','Y','R')")
    out = []
    for r in latest_per(ins, lambda r: r["business_id"], lambda r: r["date"]):
        b = biz.get(r["business_id"])
        if not b or not b.get("latitude"):
            continue
        d = r["date"]
        out.append({"id": r["business_id"], "name": title(b["name"]),
                    "address": ", ".join(p for p in (title(b.get("address")), title(b.get("city")), b.get("state", "CA"), b.get("postal_code", "")[:5]) if p),
                    "lat": round(float(b["latitude"]), 5), "lon": round(float(b["longitude"]), 5), "rk": r["result"], "date": f"{d[:4]}-{d[4:6]}-{d[6:8]}"})
    return out


def src_wake():
    base = "https://maps.wake.gov/arcgis/rest/services/Inspections/RestaurantInspectionsOpenData/MapServer"
    places = {f["attributes"]["HSISID"]: f for f in arcgis(base + "/0", geometry=True)}
    ins = [f["attributes"] for f in arcgis(base + "/1", where="SCORE IS NOT NULL")]
    out = []
    for a in latest_per(ins, lambda a: a["HSISID"], lambda a: a["DATE_"] or 0):
        f = places.get(a["HSISID"])
        if not f or not f.get("geometry") or not a.get("DATE_"):
            continue
        p, score = f["attributes"], float(a["SCORE"])
        rk = "A" if score >= 90 else "B" if score >= 80 else "C" if score >= 70 else "X"
        g = f["geometry"]
        out.append({"id": a["HSISID"], "name": title(p["NAME"]),
                    "address": ", ".join(x for x in (title(p.get("ADDRESS1")), title(p.get("CITY")), "NC", clean(p.get("POSTALCODE"))[:5]) if x),
                    "lat": round(g["y"], 5), "lon": round(g["x"], 5), "rk": rk,
                    "date": datetime.datetime.fromtimestamp(a["DATE_"] / 1000, datetime.timezone.utc).date().isoformat(),
                    "detail": f"score {score:g}", "type": title(p.get("FACILITYTYPE"))})
    return out


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
    dict(id="ny-state", name="New York State food stores", country="United States", fetch=src_ny_state,
         scheme="NYS Food Store Grades", summary="Grade A, B or C for grocery and convenience stores outside New York City, from the NYS Department of Agriculture and Markets.",
         authority="NYS Department of Agriculture and Markets", source="data.ny.gov", ratings=GRADES, type="Food store"),
    dict(id="santa-clara-ca", name="Santa Clara County, California", country="United States", fetch=src_santa_clara,
         scheme="Santa Clara County Food Placards", summary="A green (pass), yellow (conditional pass) or red (closed) placard from County Environmental Health. Covers San Jose and Silicon Valley.",
         authority="Santa Clara County Department of Environmental Health", source="Santa Clara County Open Data",
         ratings=[R("G", "✓", "Green placard – Pass", "good", 80), R("Y", "!", "Yellow placard – Conditional Pass", "fair", 50), R("R", "✗", "Red placard – Closed", "poor", 10)]),
    dict(id="wake-nc", name="Wake County, North Carolina", country="United States", fetch=src_wake,
         scheme="Wake County Restaurant Grades", summary="Grade A (90-100), B (80-89) or C (70-79) from a score out of 100. Covers Raleigh, Cary and Wake County.",
         authority="Wake County Environmental Services", source="Wake County Open Data",
         ratings=GRADES + [R("X", "<70", "Score below 70", "poor", 60)]),
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
