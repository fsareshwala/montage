#!/usr/bin/env python3
"""App Store Connect release automation helper for GitHub Actions.

Subcommands:
  preflight  Verify credentials and resolve the App Store Connect app ID.
  prepare    Create (or update) the editable iOS App Store version and set What's New.
  submit     Wait for the uploaded Xcode Cloud build to finish processing, attach it,
             and submit the version for App Review.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

import jwt

API_BASE = "https://api.appstoreconnect.apple.com"
EDITABLE_STATES = (
    "PREPARE_FOR_SUBMISSION,"
    "DEVELOPER_REJECTED,"
    "REJECTED,"
    "METADATA_REJECTED,"
    "INVALID_BINARY"
)
DEFAULT_WHATS_NEW = "Bug fixes and performance improvements."


class ASCError(RuntimeError):
    def __init__(self, status: int, body: str) -> None:
        self.status = status
        self.body = body
        super().__init__(f"App Store Connect API error (HTTP {status}): {body}")


class ASCClient:
    def __init__(self, issuer_id: str, key_id: str, private_key: str) -> None:
        self.issuer_id = issuer_id.strip()
        self.key_id = key_id.strip()
        self.private_key = private_key.strip()
        self._token: str | None = None
        self._token_issued_at: float = 0.0

    def _get_token(self) -> str:
        now = time.time()
        # Refresh every 10 minutes (Apple caps token lifetime at 20 minutes).
        if self._token is None or (now - self._token_issued_at) >= 600:
            iat = int(now)
            payload = {
                "iss": self.issuer_id,
                "iat": iat,
                "exp": iat + 900,
                "aud": "appstoreconnect-v1",
            }
            headers = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
            token = jwt.encode(payload, self.private_key, algorithm="ES256", headers=headers)
            self._token = token.decode("utf-8") if isinstance(token, bytes) else token
            self._token_issued_at = now
        return self._token

    def request(
        self,
        method: str,
        path: str,
        params: dict[str, str] | None = None,
        body: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        url = f"{API_BASE}{path}"
        if params:
            url = f"{url}?{urllib.parse.urlencode(params)}"

        data = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {
            "Authorization": f"Bearer {self._get_token()}",
            "Accept": "application/json",
        }
        if data is not None:
            headers["Content-Type"] = "application/json"

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace")
            raise ASCError(exc.code, err_body) from exc

    def resolve_app_id(self, bundle_id: str) -> str:
        resp = self.request("GET", "/v1/apps", params={"filter[bundleId]": bundle_id})
        apps = resp.get("data", [])
        if not apps:
            sys.exit(f"No app found in App Store Connect with bundle ID '{bundle_id}'.")
        app = apps[0]
        print(f"Resolved app '{app['attributes'].get('name')}' (id={app['id']}, bundleId={bundle_id})")
        return app["id"]

    def ensure_version(self, app_id: str, version_string: str) -> str:
        resp = self.request(
            "GET",
            f"/v1/apps/{app_id}/appStoreVersions",
            params={
                "filter[platform]": "IOS",
                "filter[appStoreState]": EDITABLE_STATES,
            },
        )
        editable = resp.get("data", [])
        if editable:
            existing = editable[0]
            version_id = existing["id"]
            existing_ver = existing["attributes"].get("versionString")
            state = existing["attributes"].get("appStoreState")
            if existing_ver == version_string:
                print(f"Reusing existing App Store version {version_string} (id={version_id}, state={state})")
                return version_id
            print(
                f"Updating existing editable App Store version {existing_ver} -> {version_string} "
                f"(id={version_id}, state={state})"
            )
            self.request(
                "PATCH",
                f"/v1/appStoreVersions/{version_id}",
                body={
                    "data": {
                        "type": "appStoreVersions",
                        "id": version_id,
                        "attributes": {"versionString": version_string},
                    }
                },
            )
            return version_id

        print(f"Creating new iOS App Store version {version_string}...")
        created = self.request(
            "POST",
            "/v1/appStoreVersions",
            body={
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {
                        "platform": "IOS",
                        "versionString": version_string,
                        "releaseType": "AFTER_APPROVAL",
                    },
                    "relationships": {
                        "app": {
                            "data": {
                                "type": "apps",
                                "id": app_id,
                            }
                        }
                    },
                }
            },
        )
        version_id = created["data"]["id"]
        print(f"Created App Store version {version_string} (id={version_id})")
        return version_id

    def update_whats_new(self, version_id: str, whats_new: str) -> None:
        resp = self.request("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
        localizations = resp.get("data", [])
        if not localizations:
            print("Warning: no App Store version localizations found; skipping What's New update.")
            return

        for loc in localizations:
            loc_id = loc["id"]
            locale = loc["attributes"].get("locale", "unknown")
            try:
                self.request(
                    "PATCH",
                    f"/v1/appStoreVersionLocalizations/{loc_id}",
                    body={
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": loc_id,
                            "attributes": {"whatsNew": whats_new},
                        }
                    },
                )
                print(f"Updated What's New for locale '{locale}'.")
            except ASCError as exc:
                # Initial 1.0 releases do not accept whatsNew; treat 409/422 as non-fatal.
                if exc.status in (409, 422) and "whatsNew" in exc.body:
                    print(
                        f"Skipping What's New for locale '{locale}' (not applicable for this version): "
                        f"HTTP {exc.status}"
                    )
                else:
                    raise

    def wait_for_build(
        self,
        app_id: str,
        version_string: str,
        started_after: dt.datetime,
        timeout_seconds: int = 2700,
        poll_interval: int = 30,
    ) -> tuple[str, str]:
        deadline = time.time() + timeout_seconds
        # Allow 2 minutes of clock skew before started_after.
        min_uploaded = started_after - dt.timedelta(minutes=2)
        print(
            f"Waiting for Xcode Cloud build for version {version_string} "
            f"(uploaded >= {min_uploaded.isoformat()}, timeout={timeout_seconds // 60}m)..."
        )

        attempt = 0
        while time.time() < deadline:
            attempt += 1
            try:
                resp = self.request(
                    "GET",
                    "/v1/builds",
                    params={
                        "filter[app]": app_id,
                        "filter[preReleaseVersion.platform]": "IOS",
                        "filter[preReleaseVersion.version]": version_string,
                        "sort": "-uploadedDate",
                        "limit": "5",
                    },
                )
            except ASCError as exc:
                if exc.status >= 500 or exc.status == 429:
                    print(f"[poll #{attempt}] Transient HTTP {exc.status}; retrying in {poll_interval}s...")
                    time.sleep(poll_interval)
                    continue
                raise
            except urllib.error.URLError as exc:
                print(f"[poll #{attempt}] Transient network error ({exc.reason}); retrying in {poll_interval}s...")
                time.sleep(poll_interval)
                continue

            builds = resp.get("data", [])
            recent_builds = []
            for b in builds:
                uploaded_str = b["attributes"].get("uploadedDate")
                if not uploaded_str:
                    recent_builds.append(b)
                    continue
                uploaded_dt = dt.datetime.fromisoformat(uploaded_str.replace("Z", "+00:00"))
                if uploaded_dt >= min_uploaded:
                    recent_builds.append(b)

            if recent_builds:
                build = recent_builds[0]
                build_id = build["id"]
                build_number = build["attributes"].get("version", "?")
                state = build["attributes"].get("processingState", "UNKNOWN")
                print(
                    f"[poll #{attempt}] Found build {version_string} ({build_number}) "
                    f"id={build_id} processingState={state}"
                )
                if state == "VALID":
                    if build["attributes"].get("usesNonExemptEncryption") is None:
                        print("Setting usesNonExemptEncryption=false on build...")
                        self.request(
                            "PATCH",
                            f"/v1/builds/{build_id}",
                            body={
                                "data": {
                                    "type": "builds",
                                    "id": build_id,
                                    "attributes": {"usesNonExemptEncryption": False},
                                }
                            },
                        )
                    return build_id, build_number
                if state in ("FAILED", "INVALID"):
                    sys.exit(
                        f"Build {version_string} ({build_number}) failed App Store Connect "
                        f"processing (state={state})."
                    )
            else:
                print(f"[poll #{attempt}] No processed build yet for version {version_string}...")

            time.sleep(poll_interval)

        sys.exit(
            f"Timed out after {timeout_seconds // 60} minutes waiting for build "
            f"{version_string} to appear and finish processing in App Store Connect."
        )

    def attach_build(self, version_id: str, build_id: str) -> None:
        print(f"Attaching build {build_id} to App Store version {version_id}...")
        self.request(
            "PATCH",
            f"/v1/appStoreVersions/{version_id}/relationships/build",
            body={"data": {"type": "builds", "id": build_id}},
        )
        print("Build attached.")

    def submit_for_review(self, app_id: str, version_id: str) -> tuple[str, str]:
        resp = self.request(
            "GET",
            f"/v1/apps/{app_id}/reviewSubmissions",
            params={
                "filter[platform]": "IOS",
                "filter[state]": "READY_FOR_REVIEW,UNRESOLVED_ISSUES",
            },
        )
        open_submissions = resp.get("data", [])
        if open_submissions:
            submission_id = open_submissions[0]["id"]
            print(f"Reusing open review submission (id={submission_id}).")
        else:
            created = self.request(
                "POST",
                "/v1/reviewSubmissions",
                body={
                    "data": {
                        "type": "reviewSubmissions",
                        "attributes": {"platform": "IOS"},
                        "relationships": {
                            "app": {"data": {"type": "apps", "id": app_id}},
                        },
                    }
                },
            )
            submission_id = created["data"]["id"]
            print(f"Created review submission (id={submission_id}).")

        # Check if this App Store version is already attached to the submission.
        items_resp = self.request(
            "GET",
            f"/v1/reviewSubmissions/{submission_id}/items",
            params={"include": "appStoreVersion"},
        )
        already_attached = any(
            item.get("relationships", {})
            .get("appStoreVersion", {})
            .get("data", {})
            .get("id")
            == version_id
            for item in items_resp.get("data", [])
        )
        if not already_attached:
            self.request(
                "POST",
                "/v1/reviewSubmissionItems",
                body={
                    "data": {
                        "type": "reviewSubmissionItems",
                        "relationships": {
                            "reviewSubmission": {
                                "data": {"type": "reviewSubmissions", "id": submission_id}
                            },
                            "appStoreVersion": {
                                "data": {"type": "appStoreVersions", "id": version_id}
                            },
                        },
                    }
                },
            )
            print(f"Added App Store version {version_id} to review submission {submission_id}.")

        submitted = self.request(
            "PATCH",
            f"/v1/reviewSubmissions/{submission_id}",
            body={
                "data": {
                    "type": "reviewSubmissions",
                    "id": submission_id,
                    "attributes": {"submitted": True},
                }
            },
        )
        state = submitted.get("data", {}).get("attributes", {}).get("state", "SUBMITTED")
        print(f"Submitted for App Review! submission_id={submission_id} state={state}")
        return submission_id, state


def write_gh_output(values: dict[str, str]) -> None:
    out_path = os.environ.get("GITHUB_OUTPUT")
    if not out_path:
        return
    with open(out_path, "a", encoding="utf-8") as fh:
        for k, v in values.items():
            fh.write(f"{k}={v}\n")


def make_client() -> ASCClient:
    missing = [
        name
        for name in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_PRIVATE_KEY")
        if not os.environ.get(name, "").strip()
    ]
    if missing:
        sys.exit(
            f"Missing required GitHub Secrets for App Store Connect API: {', '.join(missing)}. "
            "Add ASC_ISSUER_ID, ASC_KEY_ID, and ASC_PRIVATE_KEY in repository Settings → Secrets."
        )
    return ASCClient(
        issuer_id=os.environ["ASC_ISSUER_ID"],
        key_id=os.environ["ASC_KEY_ID"],
        private_key=os.environ["ASC_PRIVATE_KEY"],
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="App Store Connect release automation")
    sub = parser.add_subparsers(dest="command", required=True)

    p_pre = sub.add_parser("preflight")
    p_pre.add_argument("--bundle-id", required=True)

    p_prep = sub.add_parser("prepare")
    p_prep.add_argument("--app-id", required=True)
    p_prep.add_argument("--version", required=True)
    p_prep.add_argument("--whats-new", default="")

    p_sub = sub.add_parser("submit")
    p_sub.add_argument("--app-id", required=True)
    p_sub.add_argument("--version-id", required=True)
    p_sub.add_argument("--version", required=True)
    p_sub.add_argument("--started-at", required=True)
    p_sub.add_argument("--timeout-minutes", type=int, default=45)

    args = parser.parse_args()
    client = make_client()

    if args.command == "preflight":
        app_id = client.resolve_app_id(args.bundle_id)
        started_at = dt.datetime.now(dt.timezone.utc).isoformat()
        write_gh_output({"app_id": app_id, "started_at": started_at})

    elif args.command == "prepare":
        version_id = client.ensure_version(args.app_id, args.version)
        whats_new = args.whats_new.strip() or DEFAULT_WHATS_NEW
        client.update_whats_new(version_id, whats_new)
        write_gh_output({"version_id": version_id})

    elif args.command == "submit":
        started_at = dt.datetime.fromisoformat(args.started_at.replace("Z", "+00:00"))
        build_id, build_number = client.wait_for_build(
            app_id=args.app_id,
            version_string=args.version,
            started_after=started_at,
            timeout_seconds=args.timeout_minutes * 60,
        )
        client.attach_build(args.version_id, build_id)
        submission_id, state = client.submit_for_review(args.app_id, args.version_id)
        write_gh_output(
            {
                "build_id": build_id,
                "build_number": build_number,
                "submission_id": submission_id,
                "submission_state": state,
            }
        )


if __name__ == "__main__":
    main()
