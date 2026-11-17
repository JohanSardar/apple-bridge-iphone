#!/usr/bin/env python3
"""Put an uploaded build in the public TestFlight group and submit it for Beta App Review.

Run after `testflight.py --external --upload`. Every step is idempotent, so the script can be
rerun at any point. It reads the App Store Connect key from ASC_KEY_PATH, ASC_KEY_ID and
ASC_ISSUER_ID and prints no secret or contact detail. See docs/release.md.
"""
import argparse
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = Path(__file__).resolve().parent
BUNDLE = "com.johansardar.applebridge.ios"
API = "https://api.appstoreconnect.apple.com"
LOCALE = "en-US"
CONTACT_FIELDS = ["contactFirstName", "contactLastName", "contactPhone", "contactEmail"]
TEXT = HERE / "testflight"


class Stop(Exception):
    pass


def token():
    import jwt
    now = int(time.time())
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    key = Path(os.environ["ASC_KEY_PATH"]).expanduser().read_text()
    return jwt.encode(claims, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, attempts=6):
    """App Store Connect answers 500, 401 and 404 now and then for valid requests; retry those."""
    for attempt in range(attempts):
        request = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                         headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raw = error.read().decode(errors="replace")
            if error.code in (401, 404, 429, 500, 502, 503, 504) and attempt + 1 < attempts:
                time.sleep(2 + 3 * attempt)
                continue
            try:
                details = "; ".join(e.get("detail") or e.get("title", "") for e in json.loads(raw)["errors"])
            except (ValueError, KeyError, TypeError):
                details = raw[:300]
            raise Stop(f"{method} {path.split('?')[0]} failed with {error.code}: {details}") from None
        except urllib.error.URLError as error:
            if attempt + 1 < attempts:
                time.sleep(2 + 3 * attempt)
                continue
            raise Stop(f"{method} {path.split('?')[0]} failed: {error.reason}") from None


def query(path, **params):
    return path + "?" + urllib.parse.urlencode(params)


def text(name):
    return (TEXT / name).read_text().strip()


def find_build(app, version, build, wait_minutes):
    deadline = time.time() + wait_minutes * 60
    while True:
        found = call("GET", query("/v1/builds", **{"filter[app]": app, "filter[version]": build, "filter[preReleaseVersion.version]": version}))["data"]
        if found:
            state = found[0]["attributes"]["processingState"]
            if state == "VALID":
                return found[0]
            if state in ("FAILED", "INVALID"):
                raise Stop(f"Build {version} ({build}) failed processing: {state}. Check the email App Store Connect sent.")
        if time.time() > deadline:
            raise Stop(f"Build {version} ({build}) is not processed yet. Rerun this script later.")
        time.sleep(30)


def find(path, match, reads=4):
    """A list read sometimes comes back empty while the items exist. Look several times before deciding something is missing."""
    for attempt in range(reads):
        found = sorted((item for item in call("GET", path)["data"] if match(item["attributes"])), key=lambda item: item["attributes"].get("createdDate") or "")
        if found or attempt + 1 == reads:
            return found[0] if found else None
        time.sleep(5)


def upsert(collection, existing, attributes, relationship, owner):
    if existing:
        changed = {k: v for k, v in attributes.items() if existing["attributes"].get(k) != v}
        if changed:
            call("PATCH", f"/v1/{collection}/{existing['id']}", {"data": {"type": collection, "id": existing["id"], "attributes": changed}})
        return
    call("POST", f"/v1/{collection}", {"data": {"type": collection, "attributes": dict(attributes, locale=LOCALE),
                                                  "relationships": {relationship: {"data": owner}}}})


def main():
    parser = argparse.ArgumentParser(description="Add an uploaded build to the public TestFlight group; --submit sends it to Beta App Review.")
    parser.add_argument("--version", required=True, help="Marketing version the build was uploaded with, such as 0.2.0")
    parser.add_argument("--build", required=True, help="Build number the build was uploaded with")
    parser.add_argument("--group", default="Public", help="External TestFlight group that owns the public link")
    parser.add_argument("--contact", help="Private JSON with feedbackEmail and the Beta App Review contact fields; never commit it")
    parser.add_argument("--wait", type=int, default=60, help="Minutes to wait for processing")
    parser.add_argument("--submit", action="store_true", help="Submit the build for Beta App Review")
    args = parser.parse_args()
    try:
        for name in ["ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID"]:
            if not os.environ.get(name):
                raise Stop(f"Set {name} (source the release settings) first.")
        contact = json.loads(Path(args.contact).expanduser().read_text()) if args.contact else {}
        apps = call("GET", query("/v1/apps", **{"filter[bundleId]": BUNDLE}))["data"]
        if not apps:
            raise Stop(f"App Store Connect has no app record for {BUNDLE}. Ask the owner before creating one.")
        app = apps[0]["id"]
        app_ref = {"type": "apps", "id": app}

        build = find_build(app, args.version, args.build, args.wait)
        build_ref = {"type": "builds", "id": build["id"]}
        if build["attributes"].get("buildAudienceType") == "INTERNAL_ONLY":
            raise Stop("This build was exported internal-only. Export again with testflight.py --external and a new build number.")
        if build["attributes"].get("usesNonExemptEncryption") is not False:
            raise Stop("Export compliance is unanswered. ios/App/Info.plist must keep ITSAppUsesNonExemptEncryption set to false.")
        print(f"build {args.version} ({args.build}) processed, export compliance answered (no non-exempt encryption)", flush=True)

        localization = {"description": text("beta-description.txt")}
        if contact.get("feedbackEmail"):
            localization["feedbackEmail"] = contact["feedbackEmail"]
        english = lambda attributes: attributes["locale"] == LOCALE
        upsert("betaAppLocalizations", find(f"/v1/apps/{app}/betaAppLocalizations", english), localization, "app", app_ref)
        upsert("betaBuildLocalizations", find(f"/v1/builds/{build['id']}/betaBuildLocalizations", english), {"whatsNew": text("whats-new.txt")}, "build", build_ref)

        print("test information set", flush=True)
        if all(contact.get(k) for k in CONTACT_FIELDS):
            review = dict({k: contact[k] for k in CONTACT_FIELDS}, notes=text("review-notes.txt"), demoAccountRequired=False)
            call("PATCH", f"/v1/betaAppReviewDetails/{app}", {"data": {"type": "betaAppReviewDetails", "id": app, "attributes": review}})
            print("review notes and contact set", flush=True)
        else:
            print("review notes not set: App Store Connect saves them only with all four contact fields from --contact", flush=True)

        public = {"publicLinkEnabled": True, "publicLinkLimitEnabled": False, "feedbackEnabled": True}
        group = find(f"/v1/apps/{app}/betaGroups", lambda attributes: attributes["name"] == args.group)
        if not group:
            group = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": dict(public, name=args.group),
                                                               "relationships": {"app": {"data": app_ref}}}})["data"]
        if group["attributes"].get("isInternalGroup"):
            raise Stop(f"Group {args.group} is internal. Choose another --group name.")
        changed = {k: v for k, v in public.items() if group["attributes"].get(k) != v}
        if changed:
            call("PATCH", f"/v1/betaGroups/{group['id']}", {"data": {"type": "betaGroups", "id": group["id"], "attributes": changed}})
        call("POST", f"/v1/betaGroups/{group['id']}/relationships/builds", {"data": [build_ref]})
        group = call("GET", f"/v1/betaGroups/{group['id']}")["data"]
        print(f"group {args.group}: external, public link enabled={group['attributes'].get('publicLinkEnabled')}, build added", flush=True)
        print(f"public link: {group['attributes'].get('publicLink')}", flush=True)

        submission = call("GET", f"/v1/builds/{build['id']}/betaAppReviewSubmission")["data"]
        if not submission and args.submit:
            have = call("GET", f"/v1/apps/{app}/betaAppReviewDetail")["data"]["attributes"]
            missing = [k for k in CONTACT_FIELDS if not have.get(k)]
            local = find(f"/v1/apps/{app}/betaAppLocalizations", english)
            if not local or not local["attributes"].get("feedbackEmail"):
                missing.insert(0, "feedbackEmail")
            if missing:
                raise Stop("Beta App Review needs these fields in the --contact file first: " + ", ".join(missing))
            submission = call("POST", "/v1/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions",
                                                                                  "relationships": {"build": {"data": build_ref}}}})["data"]
        state = submission["attributes"]["betaReviewState"] if submission else "NOT_SUBMITTED"
        print(f"beta app review: {state}")
        if not args.submit and not submission:
            print("Rerun with --submit to send the build to Beta App Review.")
    except Stop as error:
        print(f"TestFlight public release stopped: {error}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError) as error:
        print(f"TestFlight public release failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
