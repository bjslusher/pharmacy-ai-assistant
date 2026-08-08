#!/usr/bin/env python3
"""Detect a local AWS shared profile for Pharmacy AI / Sonoran Forge deploys.

Search order:
  1. AWS_PROFILE or AWS_DEFAULT_PROFILE environment variables (if set)
  2. Preferred names: brian, default (case-insensitive match against local profiles)
  3. First remaining profile in ~/.aws/credentials or ~/.aws/config
  4. Empty string → caller should use the default AWS credential chain

Usage:
  eval $(python3 scripts/detect_aws_profile.py --export)
  PROFILE=$(python3 scripts/detect_aws_profile.py)
  terraform plan -var="aws_profile=$PROFILE"
"""
from __future__ import annotations

import argparse
import configparser
import os
import sys
from pathlib import Path

PREFERRED = ("brian", "default")


def _aws_home() -> Path:
    override = os.environ.get("AWS_SHARED_CREDENTIALS_FILE")
    if override:
        return Path(override).expanduser().parent
    return Path(os.environ.get("AWS_CONFIG_FILE", Path.home() / ".aws" / "config")).expanduser().parent


def _read_profiles() -> list[str]:
    home = _aws_home()
    names: list[str] = []
    seen: set[str] = set()

    cred_path = Path(os.environ.get("AWS_SHARED_CREDENTIALS_FILE", home / "credentials")).expanduser()
    cfg_path = Path(os.environ.get("AWS_CONFIG_FILE", home / "config")).expanduser()

    def add(name: str) -> None:
        key = name.strip()
        if not key:
            return
        low = key.lower()
        if low not in seen:
            seen.add(low)
            names.append(key)

    for path in (cred_path, cfg_path):
        if not path.is_file():
            continue
        parser = configparser.RawConfigParser()
        try:
            parser.read(path)
        except configparser.Error:
            continue
        for section in parser.sections():
            # config file uses "profile foo"; credentials uses "foo" or "default"
            if section.lower().startswith("profile "):
                add(section[8:].strip())
            else:
                add(section)
    return names


def detect_profile() -> str:
    for env_key in ("AWS_PROFILE", "AWS_DEFAULT_PROFILE"):
        val = (os.environ.get(env_key) or "").strip()
        if val:
            return val

    profiles = _read_profiles()
    if not profiles:
        return ""

    lower_map = {p.lower(): p for p in profiles}
    for preferred in PREFERRED:
        if preferred in lower_map:
            return lower_map[preferred]

    return profiles[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--export",
        action="store_true",
        help="Print shell exports for AWS_PROFILE and TF_VAR_aws_profile",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List discovered profile names and exit",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON with profile + discovered list",
    )
    args = parser.parse_args()

    discovered = _read_profiles()
    chosen = detect_profile()

    if args.list:
        for p in discovered:
            mark = " *" if p == chosen else ""
            print(f"{p}{mark}")
        return 0

    if args.json:
        import json

        print(
            json.dumps(
                {
                    "profile": chosen,
                    "discovered": discovered,
                    "preferred_order": list(PREFERRED),
                    "aws_home": str(_aws_home()),
                },
                indent=2,
            )
        )
        return 0

    if args.export:
        # Safe for eval in bash/zsh
        print(f'export AWS_PROFILE="{chosen}"')
        print(f'export TF_VAR_aws_profile="{chosen}"')
        if chosen:
            print(f'echo "Using AWS profile: {chosen}" >&2')
        else:
            print('echo "No named AWS profile found; using default credential chain" >&2')
        return 0

    # Plain profile name only (may be empty)
    print(chosen)
    return 0


if __name__ == "__main__":
    sys.exit(main())
