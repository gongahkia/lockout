#!/usr/bin/env python3
from __future__ import annotations

from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.request import Request, urlopen
import subprocess

from diagrams import Cluster, Diagram, Edge
from diagrams.custom import Custom
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "asset" / "reference"
OUTPUT_PATH = ASSET_DIR / "architecture.png"
ICON_SIZE = 256
DRAW_SIZE = 180


ICON_SPECS = {
    "github_actions": {"type": "simpleicon", "slug": "github", "color": "181717"},
    "make": {"type": "simpleicon", "slug": "gnu", "color": "A42E2B"},
    "xcodegen": {
        "type": "remote",
        "url": "https://raw.githubusercontent.com/yonaskolb/XcodeGen/master/Assets/Logo_animated.gif",
    },
    "xcode": {"type": "icns", "path": "/Applications/Xcode.app/Contents/Resources/Xcode.icns"},
    "sparkle": {
        "type": "remote",
        "url": "https://raw.githubusercontent.com/sparkle-project/Sparkle/master/Resources/Images.xcassets/AppIcon.appiconset/icon_512x512@2x.png",
    },
    "swift": {"type": "simpleicon", "slug": "swift", "color": "F05138"},
    "swiftui": {"type": "simpleicon", "slug": "apple", "color": "000000"},
    "appkit": {"type": "simpleicon", "slug": "apple", "color": "000000"},
    "combine": {"type": "simpleicon", "slug": "apple", "color": "000000"},
    "swiftdata": {"type": "simpleicon", "slug": "apple", "color": "000000"},
    "userdefaults": {"type": "simpleicon", "slug": "apple", "color": "000000"},
    "icloud": {"type": "simpleicon", "slug": "icloud", "color": "3693F3"},
    "cloudkit": {"type": "simpleicon", "slug": "icloud", "color": "3693F3"},
    "notifications": {"type": "simpleicon", "slug": "apple", "color": "000000"},
    "eventkit": {"type": "simpleicon", "slug": "apple", "color": "000000"},
    "servicemanagement": {"type": "icns", "path": "/System/Applications/System Settings.app/Contents/Resources/SystemSettings.icns"},
    "system": {"type": "simpleicon", "slug": "apple", "color": "000000"},
    "network": {"type": "simpleicon", "slug": "apple", "color": "000000"},
    "avfoundation": {"type": "icns", "path": "/System/Applications/QuickTime Player.app/Contents/Resources/AppIcon.icns"},
}


def download_bytes(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "LockOut-Architecture-Generator"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def simpleicon_url(slug: str, color: str) -> str:
    return f"https://cdn.simpleicons.org/{slug}/{color}"


def render_simpleicon(slug: str, color: str, workdir: Path) -> Image.Image:
    svg_path = workdir / f"{slug}.svg"
    png_path = workdir / f"{slug}.png"
    svg_path.write_bytes(download_bytes(simpleicon_url(slug, color)))
    subprocess.run(
        ["rsvg-convert", "-w", str(DRAW_SIZE), "-h", str(DRAW_SIZE), "-o", str(png_path), str(svg_path)],
        check=True,
    )
    return Image.open(png_path).convert("RGBA")


def render_remote_image(url: str) -> Image.Image:
    image = Image.open(BytesIO(download_bytes(url)))
    if getattr(image, "is_animated", False):
        image.seek(0)
    return image.convert("RGBA")


def render_icns(path: str, workdir: Path) -> Image.Image:
    source = Path(path)
    if not source.exists():
        raise FileNotFoundError(source)
    png_path = workdir / f"{source.stem}.png"
    subprocess.run(
        ["sips", "-s", "format", "png", str(source), "--out", str(png_path)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return Image.open(png_path).convert("RGBA")


def contain(image: Image.Image, max_size: int) -> Image.Image:
    image = image.copy()
    image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
    return image


def build_icon_asset(key: str, icon_dir: Path) -> Path:
    spec = ICON_SPECS[key]
    output = icon_dir / f"{key}.png"
    if output.exists():
        return output

    if spec["type"] == "simpleicon":
        source = render_simpleicon(spec["slug"], spec["color"], icon_dir)
    elif spec["type"] == "remote":
        source = render_remote_image(spec["url"])
    elif spec["type"] == "icns":
        source = render_icns(spec["path"], icon_dir)
    else:
        raise ValueError(f"Unsupported icon source: {spec['type']}")

    source = contain(source, DRAW_SIZE)
    canvas = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (255, 255, 255, 0))
    x = (ICON_SIZE - source.width) // 2
    y = (ICON_SIZE - source.height) // 2
    canvas.alpha_composite(source, (x, y))
    canvas.save(output)
    return output


def cluster_style(fill: str, border: str) -> dict[str, str]:
    return {
        "bgcolor": fill,
        "color": border,
        "style": "rounded,filled",
        "fontname": "Helvetica",
        "fontsize": "16",
        "margin": "20",
        "pencolor": border,
    }


def post_process_png(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    flattened = Image.new("RGBA", image.size, "white")
    flattened.alpha_composite(image)
    flattened = flattened.convert("RGB")

    border = 28
    canvas = Image.new("RGB", (flattened.width + border * 2, flattened.height + border * 2), "white")
    canvas.paste(flattened, (border, border))
    canvas.save(path)


def build_diagram() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    graph_attr = {
        "bgcolor": "white",
        "pad": "0.4",
        "splines": "spline",
        "nodesep": "0.7",
        "ranksep": "1.0",
        "fontname": "Helvetica",
        "fontsize": "20",
        "labelloc": "t",
        "labeljust": "l",
        "label": "LockOut Architecture",
    }
    node_attr = {
        "fontname": "Helvetica",
        "fontsize": "12",
        "fontcolor": "#0F172A",
        "margin": "0.12",
        "imagescale": "true",
    }
    edge_attr = {
        "fontname": "Helvetica",
        "fontsize": "11",
        "fontcolor": "#334155",
        "color": "#475569",
        "penwidth": "1.4",
    }

    with TemporaryDirectory(prefix="lockout-architecture-icons-") as tmpdir:
        icon_dir = Path(tmpdir)

        def tech(label: str, key: str) -> Custom:
            return Custom(label, str(build_icon_asset(key, icon_dir)))

        with Diagram(
            "",
            filename=str(OUTPUT_PATH.with_suffix("")),
            outformat="png",
            direction="LR",
            show=False,
            graph_attr=graph_attr,
            node_attr=node_attr,
            edge_attr=edge_attr,
        ):
            with Cluster("Build and delivery", graph_attr=cluster_style("#EEF2FF", "#C7D2FE")):
                github_actions = tech("GitHub Actions\nCI", "github_actions")
                makefile = tech("Makefile\nentrypoints", "make")
                xcodegen = tech("XcodeGen\nproject.yml", "xcodegen")
                xcode = tech("xcodebuild\nXCTest + UI tests", "xcode")
                sparkle_release = tech("Sparkle release\nDMG + notarization", "sparkle")

                github_actions >> Edge(label="runs") >> makefile >> xcodegen >> xcode >> sparkle_release

            with Cluster("LockOut macOS app target", graph_attr=cluster_style("#F8FAFC", "#CBD5E1")):
                app_delegate = tech("AppDelegate\nstartup + orchestration", "swift")
                app_shell = tech("Menu bar + main window\nSwiftUI + AppKit", "swiftui")
                break_overlay = tech("Break overlay\nAppKit presentation", "appkit")

                app_delegate >> Edge(label="creates") >> app_shell
                app_delegate >> Edge(label="presents") >> break_overlay

            with Cluster("LockOutCore Swift package", graph_attr=cluster_style("#F5F3FF", "#DDD6FE")):
                scheduler = tech("BreakScheduler\nmulti-timer engine", "combine")
                settings_profiles = tech("Settings + profiles\nrules + recovery mode", "swift")
                history_insights = tech("History repo + insights\nanalytics + exports", "swiftdata")

                scheduler >> Edge(label="uses") >> settings_profiles
                scheduler >> Edge(label="records") >> history_insights

            with Cluster("Persistence and sync", graph_attr=cluster_style("#ECFDF5", "#A7F3D0")):
                user_defaults = tech("UserDefaults\nlocal + managed prefs", "userdefaults")
                swiftdata_store = tech("SwiftData\nBreakSessionRecord", "swiftdata")
                icloud_kvs = tech("iCloud KVS\nsettings sync", "icloud")
                cloudkit = tech("CloudKit private DB\nhistory sync", "cloudkit")

            with Cluster("macOS platform services", graph_attr=cluster_style("#FFF7ED", "#FED7AA")):
                notifications = tech("UserNotifications\nbreak reminders", "notifications")
                eventkit = tech("EventKit\ncalendar-aware pauses", "eventkit")
                service_management = tech("ServiceManagement\nlaunch at login", "servicemanagement")
                system_state = tech("App Services + CG\nidle, focus, fullscreen", "system")
                network = tech("Network.framework\noffline gating", "network")
                audio = tech("AVFoundation\nbreak sounds", "avfoundation")

            xcode >> Edge(label="builds") >> app_delegate
            sparkle_release >> Edge(label="feeds updates") >> app_shell

            app_delegate >> Edge(label="owns") >> scheduler
            app_shell >> Edge(label="reads / mutates") >> scheduler
            break_overlay >> Edge(label="skip / snooze /\ncomplete") >> scheduler

            settings_profiles << Edge(label="load + save") << user_defaults
            settings_profiles >> Edge(label="push / pull") >> icloud_kvs
            history_insights >> Edge(label="persist sessions") >> swiftdata_store
            history_insights >> Edge(label="upload + fetch") >> cloudkit

            app_delegate >> Edge(label="reminders") >> notifications
            app_delegate >> Edge(label="meeting state") >> eventkit
            app_shell >> Edge(label="startup toggle") >> service_management
            app_delegate >> Edge(label="idle / focus /\nfullscreen checks") >> system_state
            cloudkit << Edge(label="queue guarded by") << network
            break_overlay >> Edge(label="plays") >> audio


if __name__ == "__main__":
    build_diagram()
    post_process_png(OUTPUT_PATH)
