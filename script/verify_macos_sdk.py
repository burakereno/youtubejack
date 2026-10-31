#!/usr/bin/env python3
"""Reject app binaries built for the wrong SDK or deployment target."""

import argparse
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError(f"Invalid version: {value!r}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def verify_build_versions(output, sdk, minimum):
    expected_sdk = version(sdk)
    expected_minimum = version(minimum)
    if expected_sdk < version("27.0"):
        raise ValueError("The build requires a macOS 27 SDK or newer; select a current Xcode.")

    records = re.findall(
        r"\bplatform\s+(\S+)\s+minos\s+(\S+)\s+sdk\s+(\S+)", output
    )
    if not records:
        raise ValueError("No macOS LC_BUILD_VERSION record found.")

    for platform, actual_minimum, actual_sdk in records:
        if platform != "MACOS":
            raise ValueError(f"Expected MACOS platform, found {platform}.")
        if version(actual_minimum) != expected_minimum:
            raise ValueError(f"Minimum macOS is {actual_minimum}; expected {minimum}.")
        if version(actual_sdk) != expected_sdk:
            raise ValueError(f"Linked SDK is {actual_sdk}; selected SDK is {sdk}.")
    return len(records)


def verify_info_plist(path, sdk, minimum):
    with Path(path).open("rb") as file:
        info = plistlib.load(file)
    if version(info.get("LSMinimumSystemVersion", "")) != version(minimum):
        raise ValueError("Info.plist minimum macOS does not match the binary.")
    name = info.get("DTSDKName", "")
    if not name.startswith("macosx") or version(name[6:]) != version(sdk):
        raise ValueError("Info.plist DTSDKName does not match the selected SDK.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--sdk", required=True)
    parser.add_argument("--minimum", default="14.0")
    parser.add_argument("--info-plist", type=Path)
    args = parser.parse_args()
    try:
        output = subprocess.check_output(
            ["xcrun", "vtool", "-show-build", str(args.binary)],
            text=True,
            stderr=subprocess.STDOUT,
        )
        slices = verify_build_versions(output, args.sdk, args.minimum)
        if args.info_plist:
            verify_info_plist(args.info_plist, args.sdk, args.minimum)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        detail = error.output.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f"macOS SDK verification failed: {detail}", file=sys.stderr)
        return 1
    print(f"Verified {slices} macOS slice(s): SDK {args.sdk}, minimum macOS {args.minimum}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
