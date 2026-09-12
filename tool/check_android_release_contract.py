#!/usr/bin/env python3
"""Fail closed when the Opto Sync Android release contract drifts."""

from __future__ import annotations

import re
import sys
from pathlib import Path


PINNED_ACTION = re.compile(r"^[ \t]*-[ \t]+uses:[ \t]+[^@\s]+@[0-9a-f]{40}(?:[ \t]+#.*)?$", re.MULTILINE)
USES_LINE = re.compile(r"^[ \t]*-[ \t]+uses:[ \t]+\S+.*$", re.MULTILINE)


def _require(text: str, markers: tuple[str, ...], scope: str, failures: list[str]) -> None:
    for marker in markers:
        if marker not in text:
            failures.append(f"{scope}: missing required marker {marker!r}")


def validate(root: Path) -> list[str]:
    failures: list[str] = []
    gradle = (root / "android/app/build.gradle.kts").read_text(encoding="utf-8")
    workflow = (root / ".github/workflows/android-beta.yml").read_text(encoding="utf-8")
    formal_ci = (root / ".github/workflows/formal-lifecycle.yml").read_text(encoding="utf-8")
    android_ignore = (root / "android/.gitignore").read_text(encoding="utf-8")

    _require(
        gradle,
        (
            'applicationId = "dev.codexsweep.opto_sync_opto_sync_flutter"',
            "validateOptoSyncReleaseSigning",
            "signingConfig = optoSyncReleaseSigningConfig",
            "androiddebugkey",
            "CN=Android Debug",
            "certificate fingerprint does not match the approved key",
            "OPTO_SYNC_ANDROID_CERT_SHA256",
        ),
        "Gradle signing",
        failures,
    )
    if 'signingConfigs.getByName("debug")' in gradle:
        failures.append("Gradle signing: debug signing fallback is forbidden")
    if "key.properties" in gradle or "key.properties" in workflow:
        failures.append("Android signing: plaintext key.properties loading is forbidden")

    _require(
        workflow,
        (
            "workflow_dispatch:",
            "environment: mobile-release",
            "persist-credentials: false",
            "OPTO_SYNC_ANDROID_KEYSTORE_BASE64",
            "OPTO_SYNC_ANDROID_KEYSTORE_PASSWORD",
            "OPTO_SYNC_ANDROID_KEY_ALIAS",
            "OPTO_SYNC_ANDROID_KEY_PASSWORD",
            "OPTO_SYNC_ANDROID_CERT_SHA256",
            "flutter pub get --enforce-lockfile",
            "flutter build appbundle --release",
            "jarsigner -verify",
            "--obfuscate",
            "--split-debug-info",
            "retention-days: 30",
            "shred -u",
        ),
        "Android beta workflow",
        failures,
    )
    action_lines = USES_LINE.findall(workflow + "\n" + formal_ci)
    unpinned = [line.strip() for line in action_lines if not PINNED_ACTION.fullmatch(line)]
    if unpinned:
        failures.append(f"GitHub Actions: actions must use full commit SHAs: {', '.join(unpinned)}")

    _require(
        formal_ci,
        (
            "python3 tool/check_android_release_contract.py",
            "python3 -m unittest tool/test_android_release_contract.py",
            "flutter pub get --enforce-lockfile",
            "unsigned Android release build unexpectedly succeeded",
            "missing protected signing inputs",
        ),
        "Formal CI release regression gate",
        failures,
    )
    _require(android_ignore, ("key.properties", "**/*.keystore", "**/*.jks", "/build/"), "Android ignores", failures)
    return failures


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    failures = validate(root)
    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1
    print("Opto Sync Android release-signing contract is fail-closed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
