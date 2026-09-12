#!/usr/bin/env python3
"""Adversarial regressions for the Opto Sync Android release policy."""

from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from tool.check_android_release_contract import validate


ROOT = Path(__file__).resolve().parents[1]
POLICY_FILES = (
    "android/app/build.gradle.kts",
    "android/.gitignore",
    ".github/workflows/android-beta.yml",
    ".github/workflows/formal-lifecycle.yml",
)


class AndroidReleaseContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for relative in POLICY_FILES:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def mutate(self, relative: str, old: str, new: str) -> None:
        path = self.root / relative
        original = path.read_text(encoding="utf-8")
        self.assertIn(old, original)
        path.write_text(original.replace(old, new, 1), encoding="utf-8")

    def assert_rejected(self, expected: str) -> None:
        self.assertTrue(any(expected in failure for failure in validate(self.root)))

    def test_current_contract_is_valid(self) -> None:
        self.assertEqual(validate(self.root), [])

    def test_rejects_debug_signing_fallback(self) -> None:
        self.mutate("android/app/build.gradle.kts", "signingConfig = optoSyncReleaseSigningConfig", 'signingConfig = signingConfigs.getByName("debug")')
        self.assert_rejected("debug signing fallback")

    def test_rejects_plaintext_key_properties(self) -> None:
        self.mutate("android/app/build.gradle.kts", "val optoSyncReleaseStorePath", 'val forbidden = "key.properties"\nval optoSyncReleaseStorePath')
        self.assert_rejected("key.properties")

    def test_rejects_unpinned_action(self) -> None:
        self.mutate(".github/workflows/android-beta.yml", "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "actions/checkout@v7")
        self.assert_rejected("full commit SHAs")

    def test_rejects_missing_cleanup(self) -> None:
        self.mutate(".github/workflows/android-beta.yml", "shred -u", "true # cleanup removed")
        self.assert_rejected("shred -u")

    def test_rejects_missing_unsigned_probe(self) -> None:
        self.mutate(".github/workflows/formal-lifecycle.yml", "unsigned Android release build unexpectedly succeeded", "release smoke check")
        self.assert_rejected("unsigned Android release build unexpectedly succeeded")

    def test_rejects_missing_expected_fingerprint(self) -> None:
        path = self.root / ".github/workflows/android-beta.yml"
        original = path.read_text(encoding="utf-8")
        self.assertIn("OPTO_SYNC_ANDROID_CERT_SHA256", original)
        path.write_text(original.replace("OPTO_SYNC_ANDROID_CERT_SHA256", "OPTO_SYNC_ANDROID_CERTIFICATE_UNCHECKED"), encoding="utf-8")
        self.assert_rejected("OPTO_SYNC_ANDROID_CERT_SHA256")

    def test_rejects_missing_debug_alias_guard(self) -> None:
        self.mutate("android/app/build.gradle.kts", "androiddebugkey", "uncheckedalias")
        self.assert_rejected("androiddebugkey")

    def test_rejects_placeholder_identity_drift(self) -> None:
        path = self.root / "android/app/build.gradle.kts"
        original = path.read_text(encoding="utf-8")
        path.write_text(original.replace("dev.codexsweep.opto_sync_opto_sync_flutter", "com.unapproved.opto"), encoding="utf-8")
        self.assert_rejected("dev.codexsweep.opto_sync_opto_sync_flutter")

    def test_rejects_unlocked_dependencies(self) -> None:
        self.mutate(".github/workflows/formal-lifecycle.yml", "flutter pub get --enforce-lockfile", "flutter pub get")
        self.assert_rejected("flutter pub get --enforce-lockfile")

    def test_rejects_unignored_android_build_output(self) -> None:
        self.mutate("android/.gitignore", "/build/", "/generated-build-output/")
        self.assert_rejected("/build/")


if __name__ == "__main__":
    unittest.main()
