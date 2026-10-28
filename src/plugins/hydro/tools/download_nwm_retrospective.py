#!/usr/bin/env python3
"""
Downloads NWM Retrospective v3.0 CHRTOUT files (CONUS, hourly) from NOAA's
public S3 archive for a given date range, one file at a time.

Bucket layout (verified directly against the live bucket):
  https://noaa-nwm-retrospective-3-0-pds.s3.amazonaws.com/CONUS/netcdf/CHRTOUT/<YYYY>/<YYYYMMDDHHMM>.CHRTOUT_DOMAIN1
No AWS credentials are needed -- the bucket is public and anonymous HTTPS GET
works directly.

Usage:
  python3 download_nwm_retrospective.py --start 2010-01-01 --end 2010-01-02 --outdir CHRTOUT
  python3 download_nwm_retrospective.py --start 2010-01-01T06:00 --end 2010-01-01T12:00 --outdir CHRTOUT
"""

import argparse
import datetime as dt
import sys

import requests

BASE_URL = "https://noaa-nwm-retrospective-3-0-pds.s3.amazonaws.com/CONUS/netcdf/CHRTOUT"


def hourly_range(start, end):
    t = start
    while t <= end:
        yield t
        t += dt.timedelta(hours=1)


def download_one(url, dest, timeout=120):
    if dest.exists():
        print(f"SKIP (already exists): {dest.name}")
        return True

    tmp = dest.with_suffix(dest.suffix + ".part")
    try:
        with requests.get(url, stream=True, timeout=timeout) as r:
            if r.status_code != 200:
                print(f"FAIL ({r.status_code}): {url}")
                return False
            with open(tmp, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024 * 1024):
                    f.write(chunk)
        tmp.rename(dest)
        print(f"OK: {dest.name} ({dest.stat().st_size:,} bytes)")
        return True
    except requests.RequestException as e:
        print(f"FAIL ({e}): {url}")
        tmp.unlink(missing_ok=True)
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--start", required=True,
                         help="start date/time, e.g. 2010-01-01 or 2010-01-01T06:00")
    parser.add_argument("--end", required=True,
                         help="end date/time (inclusive), same format as --start")
    parser.add_argument("--outdir", required=True, help="directory to save files into")
    args = parser.parse_args()

    start = dt.datetime.fromisoformat(args.start)
    end = dt.datetime.fromisoformat(args.end)
    if end < start:
        sys.exit("--end must be on or after --start")

    from pathlib import Path
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    ok_count = 0
    fail_count = 0
    for t in hourly_range(start, end):
        stamp = t.strftime("%Y%m%d%H%M")
        url = f"{BASE_URL}/{t.year}/{stamp}.CHRTOUT_DOMAIN1"
        dest = outdir / f"{stamp}.CHRTOUT_DOMAIN1"
        if download_one(url, dest):
            ok_count += 1
        else:
            fail_count += 1

    print()
    print(f"Done: {ok_count} succeeded, {fail_count} failed")


if __name__ == "__main__":
    main()
