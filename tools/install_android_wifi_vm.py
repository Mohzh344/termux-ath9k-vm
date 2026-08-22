#!/usr/bin/env python3
"""Safe installer/upgrader for android-wifi-monitor-injection-rootless.

The script downloads and verifies a GitHub Release before touching the existing
checkout. It stages the new release, runs the project's installer while the old
checkout is still available for image adoption, and removes the old checkout
only after installation succeeds.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path, PurePosixPath

REPO = "Mohzh344/android-wifi-monitor-injection-rootless"
API_URL = f"https://api.github.com/repos/{REPO}/releases/latest"
DEFAULT_PROJECT = Path.home() / "android-wifi-monitor-injection-rootless"
USER_AGENT = "android-wifi-monitor-injection-rootless-installer/1"


def fail(message: str, code: int = 1) -> "NoReturn":
    print(f"\nERROR: {message}", file=sys.stderr)
    raise SystemExit(code)


def say(message: str) -> None:
    print(f"\n==> {message}")


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def request_json(url: str) -> dict:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        fail(f"GitHub API returned HTTP {exc.code} for {url}")
    except (urllib.error.URLError, TimeoutError) as exc:
        fail(f"could not reach GitHub: {exc}")
    except json.JSONDecodeError as exc:
        fail(f"GitHub returned invalid release metadata: {exc}")
    raise AssertionError("unreachable")


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        destination.unlink(missing_ok=True)
        fail(f"download failed for {url}: {exc}")


def find_release_assets(metadata: dict, archive_mode: str) -> tuple[str, str, str, str]:
    tag = metadata.get("tag_name")
    assets = metadata.get("assets") or []
    if not tag or not isinstance(assets, list):
        fail("GitHub release metadata does not contain a usable tag or asset list")

    if archive_mode == "full":
        marker = "full-lite-ready.tar.gz"
    elif archive_mode == "update":
        marker = "update.tar.gz"
    else:
        raise ValueError(archive_mode)

    archive_asset = next(
        (asset for asset in assets if str(asset.get("name", "")).endswith(marker)), None
    )
    if not archive_asset:
        fail(f"latest release {tag} has no {marker} archive")

    archive_name = str(archive_asset.get("name"))
    checksum_asset = next(
        (
            asset
            for asset in assets
            if str(asset.get("name", ""))
            in {f"{archive_name}.sha256", f"{archive_name}.sha256sum"}
        ),
        None,
    )
    if not checksum_asset:
        fail(f"latest release {tag} has no checksum asset for {archive_name}")

    archive_url = str(archive_asset.get("browser_download_url"))
    checksum_url = str(checksum_asset.get("browser_download_url"))
    if not archive_url or not checksum_url:
        fail("release assets do not contain download URLs")
    return tag, archive_name, archive_url, checksum_url


def parse_expected_sha256(checksum_file: Path, archive_name: str) -> str:
    text = checksum_file.read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        match = re.match(r"^([0-9a-fA-F]{64})\s+(?:\*|)(.+?)\s*$", line)
        if not match:
            continue
        listed_name = Path(match.group(2)).name
        if listed_name == archive_name:
            return match.group(1).lower()
    fail(f"checksum file does not contain a SHA-256 entry for {archive_name}")
    raise AssertionError("unreachable")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def safe_member_path(name: str) -> Path:
    # Release archives use POSIX paths even when extracted on another host.
    pure = PurePosixPath(name)
    if pure.is_absolute() or ".." in pure.parts:
        fail(f"refusing unsafe archive path: {name}")
    if not pure.parts:
        fail("refusing an empty archive member path")
    return Path(*pure.parts)


def sparse_payload_size(member: tarfile.TarInfo) -> int:
    sparse = getattr(member, "sparse", None)
    if sparse:
        return sum(length for _offset, length in sparse)
    return member.size


def ensure_extraction_space(archive: Path, destination: Path, members: list[tarfile.TarInfo]) -> None:
    extracted_bytes = sum(sparse_payload_size(member) for member in members if member.isfile())
    safety_margin = 256 * 1024 * 1024
    free_bytes = shutil.disk_usage(destination.parent).free
    required = extracted_bytes + safety_margin
    if free_bytes < required:
        fail(
            f"not enough free storage for safe extraction: need about {required} bytes, "
            f"but only {free_bytes} bytes are available"
        )
    print(
        f"Extraction estimate: {extracted_bytes} allocated bytes "
        f"(+{safety_margin} bytes safety margin)"
    )


def write_tar_member_sparse(source, output, member: tarfile.TarInfo) -> None:
    sparse = getattr(member, "sparse", None)
    if not sparse:
        shutil.copyfileobj(source, output, length=1024 * 1024)
        return
    for offset, length in sparse:
        output.seek(offset)
        remaining = length
        while remaining:
            chunk = source.read(min(1024 * 1024, remaining))
            if not chunk:
                fail(f"truncated sparse archive member: {member.name}")
            output.write(chunk)
            remaining -= len(chunk)
    output.truncate(member.size)


def safe_extract(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, mode="r:gz") as tar:
        members = tar.getmembers()
        ensure_extraction_space(archive, destination, members)
        for member in members:
            relative = safe_member_path(member.name)
            target = (destination / relative).resolve()
            root = destination.resolve()
            if target != root and root not in target.parents:
                fail(f"refusing archive member outside extraction directory: {member.name}")
            if member.issym() or member.islnk():
                link_target = PurePosixPath(member.linkname)
                if link_target.is_absolute() or ".." in link_target.parts:
                    fail(f"refusing unsafe archive link: {member.name} -> {member.linkname}")
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open("wb") as output:
                    if source is None:
                        fail(f"could not read archive member: {member.name}")
                    write_tar_member_sparse(source, output, member)
                os.chmod(target, member.mode & 0o7777)
            elif member.issym():
                target.parent.mkdir(parents=True, exist_ok=True)
                os.symlink(member.linkname, target)
            elif member.islnk():
                target.parent.mkdir(parents=True, exist_ok=True)
                link_source = (target.parent / member.linkname).resolve()
                if root not in link_source.parents and link_source != root:
                    fail(f"refusing hard link outside extraction directory: {member.name}")
                os.link(link_source, target)
            else:
                fail(f"refusing unsupported archive member: {member.name}")


def locate_release_root(extracted: Path) -> Path:
    candidates = [extracted]
    candidates.extend(path for path in extracted.iterdir() if path.is_dir())
    for candidate in candidates:
        if (candidate / "bin" / "install-termux.sh").is_file():
            return candidate.resolve()
    fail("archive was verified but no bin/install-termux.sh was found")
    raise AssertionError("unreachable")


def default_state_root() -> Path:
    explicit = os.environ.get("VM_STATE_ROOT")
    if explicit:
        return Path(explicit).expanduser()
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        return Path(xdg).expanduser() / "android-wifi-monitor-injection-rootless"
    return Path.home() / ".local" / "share" / "android-wifi-monitor-injection-rootless"


def has_persistent_images(state_root: Path) -> bool:
    return any(
        (state_root / variant / filename).is_file()
        for variant, filename in (
            ("full", "alpine-ath9k.img"),
            ("lite", "alpine-ath9k-v030-lite.img"),
        )
    )


def has_legacy_images(directory: Path) -> bool:
    return any(
        (directory / variant / "guest" / filename).is_file()
        for variant, filename in (
            ("full", "alpine-ath9k.img"),
            ("lite", "alpine-ath9k-v030-lite.img"),
        )
    )


def resolve_existing_directory(path: Path, label: str) -> Path | None:
    if not path.exists():
        return None
    if path.is_symlink():
        fail(f"{label} is a symbolic link; refusing to delete it: {path}")
    if not path.is_dir():
        fail(f"{label} exists but is not a directory: {path}")
    return path.resolve()


def run_checked(command: list[str], *, cwd: Path, env: dict[str, str]) -> None:
    say("Running: " + " ".join(command))
    result = subprocess.run(command, cwd=cwd, env=env)
    if result.returncode != 0:
        fail(f"command failed with exit code {result.returncode}: {' '.join(command)}")


def post_install_check(project: Path, state_root: Path) -> None:
    vmctl = project / "bin" / "vmctl.sh"
    launcher = project / "bin" / "vm-launcher.sh"
    if not vmctl.is_file() or not launcher.is_file():
        fail("installation finished but vmctl.sh or vm-launcher.sh is missing")

    env = os.environ.copy()
    env["VM_STATE_ROOT"] = str(state_root)
    available = []
    for variant, filename in (
        ("full", "alpine-ath9k.img"),
        ("lite", "alpine-ath9k-v030-lite.img"),
    ):
        if (state_root / variant / filename).is_file():
            available.append(variant)
            info = subprocess.run([str(vmctl), "info", f"--{variant}"], cwd=project, env=env)
            if info.returncode != 0:
                fail(f"post-install info check failed for {variant}")
            dry = subprocess.run(
                [str(launcher), f"--{variant}", "--dry-run", "--non-interactive"],
                cwd=project,
                env=env,
            )
            if dry.returncode != 0:
                fail(f"post-install launcher dry-run failed for {variant}")
    if not available:
        fail(f"installer finished but no persistent Full/Lite image exists in {state_root}")
    say("Post-install verification passed for: " + ", ".join(available))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Safely replace the Termux project checkout with the latest verified GitHub Release."
    )
    parser.add_argument(
        "--project-dir",
        type=Path,
        default=DEFAULT_PROJECT,
        help=f"new project directory (default: {DEFAULT_PROJECT})",
    )
    parser.add_argument(
        "--old-dir",
        type=Path,
        default=None,
        help="old checkout containing existing Full/Lite images; defaults to --project-dir if it exists",
    )
    parser.add_argument(
        "--state-dir",
        type=Path,
        default=None,
        help="persistent VM data directory; defaults to VM_STATE_ROOT or the standard XDG path",
    )
    parser.add_argument(
        "--archive",
        choices=("auto", "full", "update"),
        default="auto",
        help="release archive: auto chooses full for a fresh install and update when data/images exist",
    )
    parser.add_argument("--yes", action="store_true", help="do not ask for deletion confirmation")
    parser.add_argument(
        "--download-only",
        action="store_true",
        help="download and verify the selected archive, but do not extract, install, or delete anything",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show the release and deletion plan without downloading or changing anything",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project = args.project_dir.expanduser()
    old_candidate = args.old_dir.expanduser() if args.old_dir else project
    old_dir = resolve_existing_directory(old_candidate, "old checkout")
    project_resolved = project.resolve()
    state_root = (args.state_dir.expanduser() if args.state_dir else default_state_root()).resolve()

    if old_dir and project_resolved != old_dir and (old_dir in project_resolved.parents or project_resolved in old_dir.parents):
        fail(
            "the new project directory and old checkout must not be nested; "
            "choose two independent directories"
        )
    if old_dir and (state_root == old_dir or old_dir in state_root.parents):
        fail(
            "VM_STATE_ROOT is inside the checkout that will be deleted. "
            "Choose an external --state-dir first so VM data cannot be removed."
        )

    if args.archive == "auto":
        mode = "update" if has_persistent_images(state_root) or (old_dir and has_legacy_images(old_dir)) else "full"
    else:
        mode = args.archive

    if args.dry_run:
        metadata = request_json(API_URL)
        tag = metadata.get("tag_name", "unknown")
        print(f"Release: {tag}")
        print(f"Archive mode: {mode}")
        print(f"New project directory: {project.resolve()}")
        print(f"Old checkout: {old_dir or '(none)'}")
        print(f"Persistent VM data: {state_root}")
        print("No files were downloaded, deleted, or modified.")
        return 0

    if not args.download_only:
        if not command_exists("bash"):
            fail("bash is required")
        if not command_exists("pkg"):
            fail("this script must run inside Termux, where the pkg command is available")
    if old_dir and project.resolve() != old_dir and project.exists():
        fail(f"new project directory already exists; choose another path or remove it manually: {project}")

    metadata = request_json(API_URL)
    tag, archive_name, archive_url, checksum_url = find_release_assets(metadata, mode)
    say(f"Selected GitHub release {tag}: {archive_name}")
    if old_dir:
        print(f"Existing checkout will be used for image adoption: {old_dir}")
    print(f"Persistent VM data will be kept at: {state_root}")

    if old_dir and not args.yes and not args.download_only:
        answer = input(
            f"\nAfter a successful install, permanently delete the old checkout {old_dir}? [y/N]: "
        ).strip().lower()
        if answer not in {"y", "yes"}:
            fail("installation cancelled; the old checkout was not changed", code=2)

    project.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="android-wifi-vm-install-", dir=project.parent) as temporary:
        work = Path(temporary)
        archive_path = work / archive_name
        checksum_path = work / f"{archive_name}.sha256"
        say("Downloading release archive")
        download(archive_url, archive_path)
        say("Downloading SHA-256 checksum")
        download(checksum_url, checksum_path)
        expected = parse_expected_sha256(checksum_path, archive_name)
        actual = sha256_file(archive_path)
        if actual != expected:
            fail(f"SHA-256 mismatch; expected {expected}, got {actual}")
        say(f"SHA-256 verified: {actual}")

        if args.download_only:
            print(f"Verified archive: {archive_path}")
            print(f"SHA-256: {actual}")
            return 0

        extracted = work / "extracted"
        say("Extracting the verified archive into a staging directory while preserving sparse images")
        safe_extract(archive_path, extracted)
        staged_root = locate_release_root(extracted)
        os.chdir(staged_root)

        env = os.environ.copy()
        env["VM_STATE_ROOT"] = str(state_root)
        if old_dir:
            env["VM_LEGACY_DIR"] = str(old_dir)
        say("Installing Termux dependencies and adopting persistent VM images")
        run_checked(["bash", "bin/install-termux.sh"], cwd=staged_root, env=env)

        # The installer has now copied/adopted images and completed all package
        # installation. Only at this point is it safe to replace the old checkout.
        old_checkout_backup: Path | None = None
        if project.exists():
            if project.is_symlink() or not project.is_dir():
                fail(f"refusing to replace non-directory project path: {project}")
            # Keep the old checkout recoverable until the new staged checkout has
            # been moved successfully. This matters when --old-dir equals the
            # destination project directory.
            fd, backup_name = tempfile.mkstemp(prefix=f".{project.name}.old-", dir=project.parent)
            os.close(fd)
            os.unlink(backup_name)
            old_checkout_backup = Path(backup_name)
            say(f"Temporarily moving the existing checkout: {project}")
            shutil.move(str(project), str(old_checkout_backup))
        try:
            # The release normally has a single top-level directory. Moving the
            # actual root keeps the final checkout free of an extra nesting level.
            shutil.move(str(staged_root), str(project))
        except Exception:
            if old_checkout_backup and old_checkout_backup.exists() and not project.exists():
                shutil.move(str(old_checkout_backup), str(project))
            raise
        if old_checkout_backup and old_checkout_backup.exists():
            say(f"Removing the old checkout after successful installation: {old_checkout_backup}")
            shutil.rmtree(old_checkout_backup)
        if old_dir and old_dir != project_resolved and old_dir.exists():
            say(f"Removing the old checkout after successful installation: {old_dir}")
            shutil.rmtree(old_dir)

    post_install_check(project, state_root)
    print("\nInstallation completed successfully.")
    print(f"Project: {project}")
    print(f"Persistent VM data: {state_root}")
    print("The old checkout was removed only after checksum verification and installer success.")
    print(f"To enter the new directory in your current Termux shell, run:\n  cd {project}")
    print(f"Recommended start command:\n  bash {project}/bin/vm-launcher.sh")
    return 0


if __name__ == "__main__":
    main()
