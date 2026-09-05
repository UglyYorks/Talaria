#!/usr/bin/env python3
import argparse
import gzip
import io
import os
import re
import shutil
import stat
import tarfile
import tempfile
import urllib.request
from pathlib import Path


ARCH = "aarch64"
BASE_URL = "https://dl-cdn.alpinelinux.org/alpine"
DEFAULT_PACKAGES = (
    "python3", "ca-certificates-bundle", "bash", "curl", "git", "xz",
    "build-base", "ripgrep", "ncurses-terminfo-base",
)
DEPENDENCY_SPLIT_RE = re.compile(r"([<>=~].*)$")


class PackageIndex:
    def __init__(self, release, repositories):
        self.release = release
        self.repositories = repositories
        self.packages = {}
        self.providers = {}

    def load(self):
        for repository in self.repositories:
            index_url = f"{BASE_URL}/{self.release}/{repository}/{ARCH}/APKINDEX.tar.gz"
            with urllib.request.urlopen(index_url, timeout=60) as response:
                data = response.read()
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
                index_text = archive.extractfile("APKINDEX").read().decode("utf-8")
            for block in index_text.strip().split("\n\n"):
                package = self._parse_block(block, repository)
                name = package.get("P")
                if not name:
                    continue
                self.packages[name] = package
                self.providers[name] = name
                for provided in package.get("p", "").split():
                    self.providers[self._dependency_key(provided)] = name

    def resolve(self, requested):
        resolved = []
        seen = set()
        stack = list(reversed(requested))
        while stack:
            dependency = stack.pop()
            key = self._dependency_key(dependency)
            if key.startswith("/") or key in seen:
                continue
            package_name = self.providers.get(key)
            if not package_name:
                raise RuntimeError(f"Could not resolve Alpine package dependency: {dependency}")
            if package_name in seen:
                continue
            seen.add(package_name)
            package = self.packages[package_name]
            resolved.append(package)
            dependencies = [item for item in package.get("D", "").split() if item]
            stack.extend(reversed(dependencies))
        return resolved

    def package_url(self, package):
        return f"{BASE_URL}/{self.release}/{package['repository']}/{ARCH}/{package['P']}-{package['V']}.apk"

    @staticmethod
    def _parse_block(block, repository):
        package = {"repository": repository}
        for line in block.splitlines():
            if len(line) > 2 and line[1] == ":":
                key = line[0]
                value = line[2:]
                package[key] = f"{package[key]} {value}" if key in package else value
        return package

    @staticmethod
    def _dependency_key(value):
        return DEPENDENCY_SPLIT_RE.sub("", value)


def download_to_cache(url, cache_dir):
    cache_dir.mkdir(parents=True, exist_ok=True)
    destination = cache_dir / url.rsplit("/", 1)[-1]
    if destination.exists() and destination.stat().st_size > 0:
        return destination

    temporary = destination.with_suffix(destination.suffix + ".tmp")
    with urllib.request.urlopen(url, timeout=120) as response:
        temporary.write_bytes(response.read())
    temporary.replace(destination)
    return destination


def extract_apk(apk_path, destination):
    with tarfile.open(apk_path, mode="r:gz") as archive:
        for member in archive.getmembers():
            if member.name.startswith("."):
                continue
            target = safe_target(destination, member.name)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                target.chmod(member.mode & 0o7777)
            elif member.issym():
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.exists() or target.is_symlink():
                    target.unlink()
                target.symlink_to(member.linkname)
            elif member.islnk():
                link_target = safe_target(destination, member.linkname)
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.exists() or target.is_symlink():
                    target.unlink()
                if link_target.exists():
                    os.link(link_target, target)
                else:
                    target.symlink_to(member.linkname)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(member.mode & 0o7777)


def safe_target(root, name):
    relative = Path(name.lstrip("/"))
    if relative.is_absolute() or ".." in relative.parts:
        raise RuntimeError(f"Unsafe archive path: {name}")
    return root / relative


def install_file(source, destination, mode):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    destination.chmod(mode)


def write_text(destination, text, mode=0o644):
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8")
    destination.chmod(mode)


def merge_directory_contents(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    for child in source.iterdir():
        target = destination / child.name
        if child.is_dir() and not child.is_symlink() and target.is_dir() and not target.is_symlink():
            merge_directory_contents(child, target)
            child.rmdir()
            continue
        if target.exists() or target.is_symlink():
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink()
        shutil.move(str(child), str(target))


def normalize_usr_merge(root):
    for link_name, target_name in (("bin", "usr/bin"), ("sbin", "usr/sbin"), ("lib", "usr/lib")):
        link_path = root / link_name
        target_path = root / target_name
        if link_path.is_symlink():
            continue
        if link_path.exists():
            if not link_path.is_dir():
                raise RuntimeError(f"Cannot normalize non-directory /{link_name}")
            merge_directory_contents(link_path, target_path)
            link_path.rmdir()
        link_path.symlink_to(target_name)


def extract_zboot_kernel(source, destination):
    data = source.read_bytes()
    if data[0x38:0x3c] == b"ARMd":
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        return

    if len(data) < 0x20 or data[4:8] != b"zimg":
        raise RuntimeError(f"Unsupported ARM64 kernel image format: {source}")

    payload_offset = int.from_bytes(data[8:12], "little")
    payload_size = int.from_bytes(data[12:16], "little")
    compression = data[24:32].split(b"\0", 1)[0]
    payload = data[payload_offset:payload_offset + payload_size]
    if len(payload) != payload_size:
        raise RuntimeError(f"ARM64 zboot payload is truncated: {source}")

    if compression == b"gzip":
        kernel = gzip.decompress(payload)
    elif compression in (b"", b"none"):
        kernel = payload
    else:
        raise RuntimeError(f"Unsupported ARM64 zboot compression: {compression.decode('ascii', errors='replace')}")

    if kernel[0x38:0x3c] != b"ARMd":
        raise RuntimeError(f"Extracted ARM64 kernel payload is not a bootable Image: {source}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(kernel)


def align4(value):
    return (value + 3) & ~3


def strip_cpio_trailer(data):
    offset = 0
    while offset + 110 <= len(data):
        entry_start = offset
        magic = data[offset:offset + 6]
        if magic not in (b"070701", b"070702"):
            raise RuntimeError("Base initramfs is not a newc cpio archive.")
        fields = [
            int(data[offset + 6 + index * 8:offset + 14 + index * 8], 16)
            for index in range(13)
        ]
        file_size = fields[6]
        name_size = fields[11]
        name_start = offset + 110
        name_end = name_start + name_size
        name = data[name_start:name_end - 1].decode("utf-8", errors="replace")
        file_start = align4(name_end)
        offset = align4(file_start + file_size)
        if name == "TRAILER!!!":
            return data[:entry_start]
    raise RuntimeError("Base initramfs cpio trailer was not found.")


def cpio_entry(name, mode, data=b"", uid=0, gid=0, inode=1):
    name_bytes = name.encode("utf-8") + b"\0"
    header = (
        "070701"
        f"{inode:08x}"
        f"{mode:08x}"
        f"{uid:08x}"
        f"{gid:08x}"
        f"{1:08x}"
        f"{0:08x}"
        f"{len(data):08x}"
        f"{0:08x}"
        f"{0:08x}"
        f"{0:08x}"
        f"{0:08x}"
        f"{len(name_bytes):08x}"
        f"{0:08x}"
    ).encode("ascii")
    output = bytearray(header)
    output.extend(name_bytes)
    output.extend(b"\0" * (align4(len(output)) - len(output)))
    output.extend(data)
    output.extend(b"\0" * (align4(len(output)) - len(output)))
    return bytes(output)


def build_overlay_cpio(root):
    entries = []
    inode = 1
    for current_root, directory_names, file_names in os.walk(root):
      directory_names.sort()
      file_names.sort()
      current = Path(current_root)
      for name in directory_names + file_names:
          path = current / name
          relative = path.relative_to(root).as_posix()
          info = path.lstat()
          inode += 1
          if stat.S_ISDIR(info.st_mode):
              entries.append(cpio_entry(relative, stat.S_IFDIR | (info.st_mode & 0o7777), inode=inode))
          elif stat.S_ISLNK(info.st_mode):
              target = os.readlink(path).encode("utf-8")
              entries.append(cpio_entry(relative, stat.S_IFLNK | 0o777, target, inode=inode))
          elif stat.S_ISREG(info.st_mode):
              entries.append(cpio_entry(relative, stat.S_IFREG | (info.st_mode & 0o7777), path.read_bytes(), inode=inode))
    inode += 1
    entries.append(cpio_entry("TRAILER!!!", 0, inode=inode))
    return b"".join(entries)


def main():
    parser = argparse.ArgumentParser(description="Build Talaria's Linux agent initramfs.")
    parser.add_argument("--alpine-release", required=True)
    parser.add_argument("--zboot-kernel", required=True, type=Path)
    parser.add_argument("--kernel-output", required=True, type=Path)
    parser.add_argument("--base-initrd", required=True, type=Path)
    parser.add_argument("--modloop", required=True, type=Path)
    parser.add_argument("--agent-script", required=True, type=Path)
    parser.add_argument("--terminal-script", required=True, type=Path)
    parser.add_argument("--init-script", required=True, type=Path)
    parser.add_argument("--cache-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    extract_zboot_kernel(args.zboot_kernel, args.kernel_output)

    package_index = PackageIndex(args.alpine_release, ("main", "community"))
    package_index.load()
    packages = package_index.resolve(DEFAULT_PACKAGES)

    with tempfile.TemporaryDirectory() as directory:
        overlay = Path(directory) / "overlay"
        overlay.mkdir()
        for package in packages:
            apk_path = download_to_cache(package_index.package_url(package), args.cache_dir)
            extract_apk(apk_path, overlay)

        normalize_usr_merge(overlay)
        for module in args.agent_script.parent.glob("*.py"):
            install_file(module, overlay / "opt/talaria" / module.name, 0o644)
        install_file(args.terminal_script, overlay / "opt/talaria/terminal_service.py", 0o644)
        write_text(overlay / "etc/profile.d/talaria-terminal.sh",
                   'export PATH="$HOME/.hermes/hermes-agent/venv/bin:$HOME/.local/bin:$PATH"\n')
        install_file(args.init_script, overlay / "talaria-init", 0o755)
        install_file(args.modloop, overlay / "modloop-virt", 0o644)
        write_text(overlay / "etc/hosts", "127.0.0.1 localhost\n::1 localhost\n")
        write_text(
            overlay / "usr/share/udhcpc/default.script",
            """#!/bin/sh
case \"$1\" in
  deconfig)
    /usr/bin/busybox ip addr flush dev \"$interface\"
    ;;
  bound|renew)
    /usr/bin/busybox ip addr flush dev \"$interface\"
    /usr/bin/busybox ip addr add \"$ip/24\" dev \"$interface\"
    for gateway in $router; do
      /usr/bin/busybox ip route add default via \"$gateway\" dev \"$interface\" && break
    done
    : > /etc/resolv.conf
    for server in $dns; do echo \"nameserver $server\" >> /etc/resolv.conf; done
    if [ ! -s /etc/resolv.conf ]; then
      for gateway in $router; do echo \"nameserver $gateway\" >> /etc/resolv.conf; break; done
    fi
    ;;
esac
exit 0
""",
            0o755,
        )
        write_text(overlay / "opt/talaria/runtime.txt", "linux-aarch64 alpine python vsock\n")

        base_data = gzip.decompress(args.base_initrd.read_bytes())
        combined = strip_cpio_trailer(base_data) + build_overlay_cpio(overlay)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(gzip.compress(combined, compresslevel=9))


if __name__ == "__main__":
    raise SystemExit(main())
