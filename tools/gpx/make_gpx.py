#!/usr/bin/env python3
"""Generate the GPX files used by ReachCore's unit tests and Xcode's location simulation.

Run from the repo root:  python3 tools/gpx/make_gpx.py

Each route is a list of legs. A leg is either a walk/ride along waypoints at a
given speed, a dwell (standing still with GPS jitter), or a gap (no fixes at
all, like being underground). Output uses <wpt> elements because that's what
Xcode's simulator plays back; <hacc> is Reach's own extension for accuracy.
Routes follow real streets approximately; they don't need to be survey-exact.
"""
import math
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUTS = [ROOT / "ReachCore/Tests/ReachCoreTests/Fixtures", ROOT / "Reach/Simulation"]
START = datetime(2026, 10, 1, 13, 0, 0, tzinfo=timezone.utc)  # 9:00 in New York
EARTH = 6371008.8


def dist(a, b):
    la1, la2 = math.radians(a[0]), math.radians(b[0])
    dla, dlo = la2 - la1, math.radians(b[1] - a[1])
    h = math.sin(dla / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin(dlo / 2) ** 2
    return 2 * EARTH * math.asin(min(1, math.sqrt(h)))


def offset(p, north_m, east_m):
    return (p[0] + north_m / 111_320, p[1] + east_m / (111_320 * math.cos(math.radians(p[0]))))


class Route:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.t = 0.0
        self.pos = None
        self.points = []  # (seconds from start, lat, lon, hacc)

    def at(self, p):
        self.pos = p
        return self

    def move(self, waypoints, speed, interval=1.0, hacc=5.0, noise=2.0):
        for target in waypoints:
            d = dist(self.pos, target)
            steps = max(1, round(d / (speed * interval)))
            a = self.pos
            for i in range(1, steps + 1):
                f = i / steps
                p = (a[0] + (target[0] - a[0]) * f, a[1] + (target[1] - a[1]) * f)
                self.t += d / steps / speed
                j = offset(p, self.rng.gauss(0, noise), self.rng.gauss(0, noise))
                self.points.append((self.t, j[0], j[1], hacc))
            self.pos = target
        return self

    def dwell(self, seconds, interval=5.0, hacc=12.0, jitter=6.0):
        end = self.t + seconds
        while self.t + interval <= end:
            self.t += interval
            j = offset(self.pos, self.rng.gauss(0, jitter), self.rng.gauss(0, jitter))
            self.points.append((self.t, j[0], j[1], hacc))
        self.t = end
        return self

    def gap(self, seconds, reappear_at):
        self.t += seconds
        self.pos = reappear_at
        return self

    def write(self, name, description):
        lines = ['<?xml version="1.0" encoding="UTF-8"?>',
                 '<gpx version="1.1" creator="Reach tools/gpx/make_gpx.py" xmlns="http://www.topografix.com/GPX/1/1">',
                 f'  <metadata><desc>{description}</desc></metadata>']
        for t, lat, lon, hacc in self.points:
            when = START + timedelta(milliseconds=round(t * 1000))
            stamp = when.strftime("%Y-%m-%dT%H:%M:%S.") + f"{when.microsecond // 1000:03d}Z"
            lines.append(f'  <wpt lat="{lat:.7f}" lon="{lon:.7f}"><time>{stamp}</time><hacc>{hacc:.0f}</hacc></wpt>')
        lines.append('</gpx>')
        text = "\n".join(lines) + "\n"
        for out in OUTPUTS:
            out.mkdir(parents=True, exist_ok=True)
            (out / f"{name}.gpx").write_text(text)
        print(f"{name}.gpx: {len(self.points)} points, {self.t / 60:.1f} min")


WALK = 1.4   # m/s
BARCLAYS = (40.68265, -73.97539)
FLATBUSH_7TH_AVE = (40.67900, -73.97300)
GRAND_ARMY_PLAZA = (40.67450, -73.97040)
ATLANTIC_AVE_EAST = (40.68110, -73.96550)
UNION_SQUARE = (40.73560, -73.99050)
UNION_SQUARE_WEST = (40.73700, -73.99250)

Route(1).at(BARCLAYS).move([FLATBUSH_7TH_AVE, GRAND_ARMY_PLAZA], WALK).write(
    "WalkBarclaysToGrandArmyPlaza",
    "Walk from Barclays Center down Flatbush Ave to Grand Army Plaza, about 1 km.")

Route(2).at(BARCLAYS).move([ATLANTIC_AVE_EAST], WALK).dwell(6 * 60).move([BARCLAYS], WALK).write(
    "WalkDwellWalk",
    "Walk east on Atlantic Ave, stand still for 6 minutes, walk back.")

Route(3).at(GRAND_ARMY_PLAZA).move([BARCLAYS], WALK).gap(14 * 60, UNION_SQUARE).move([UNION_SQUARE_WEST], WALK).write(
    "WalkSubwayGapWalk",
    "Walk to Atlantic Av-Barclays Ctr, 14 minutes with no GPS (subway), reappear at Union Square and walk on.")
