import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[2] / "script" / "verify_macos_sdk.py"
SPEC = importlib.util.spec_from_file_location("verify_macos_sdk", SCRIPT)
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


def build_record(sdk="27.0", minimum="14.0", platform="MACOS"):
    return f"""Load command 11
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform {platform}
    minos {minimum}
      sdk {sdk}
   ntools 1
"""


class MacOSSDKVerificationTests(unittest.TestCase):
    def test_current_sdk_keeps_macos_14_support(self):
        self.assertEqual(verifier.verify_build_versions(build_record(), "27.0", "14.0"), 1)

    def test_legacy_sdk_stamp_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Linked SDK is 14.0"):
            verifier.verify_build_versions(build_record(sdk="14.0"), "27.0", "14.0")

    def test_every_architecture_must_match(self):
        output = build_record() + build_record(sdk="14.0")
        with self.assertRaisesRegex(ValueError, "Linked SDK"):
            verifier.verify_build_versions(output, "27.0", "14.0")

    def test_raised_deployment_target_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Minimum macOS is 15.0"):
            verifier.verify_build_versions(build_record(minimum="15.0"), "27.0", "14.0")

    def test_missing_build_record_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "No macOS"):
            verifier.verify_build_versions("not a Mach-O build record", "27.0", "14.0")

    def test_old_toolchain_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "macOS 27 SDK or newer"):
            verifier.verify_build_versions(build_record(sdk="15.0"), "15.0", "14.0")

    def test_other_platform_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Expected MACOS"):
            verifier.verify_build_versions(build_record(platform="IOS"), "27.0", "14.0")

    def test_equivalent_version_notation_is_accepted(self):
        self.assertEqual(verifier.verify_build_versions(build_record(), "27.0.0", "14"), 1)

    def test_bundle_metadata_must_match_linked_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            with path.open("wb") as file:
                plistlib.dump({"LSMinimumSystemVersion": "14.0", "DTSDKName": "macosx27.0"}, file)
            verifier.verify_info_plist(path, "27.0", "14.0")
            with path.open("wb") as file:
                plistlib.dump({"LSMinimumSystemVersion": "14.0", "DTSDKName": "macosx14.0"}, file)
            with self.assertRaisesRegex(ValueError, "DTSDKName"):
                verifier.verify_info_plist(path, "27.0", "14.0")


if __name__ == "__main__":
    unittest.main()
