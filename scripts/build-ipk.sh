#!/bin/sh
set -eu

PACKAGE_NAME="open-box"
PACKAGE_RELEASE="${PACKAGE_RELEASE:-1}"
PACKAGE_ARCH="x86_64"
SOURCE_URL="${SOURCE_URL:-}"
SOURCE_SHA256_URL="${SOURCE_SHA256_URL:-}"
SOURCE_TARBALL="${SOURCE_TARBALL:-}"
SOURCE_SHA256_FILE="${SOURCE_SHA256_FILE:-}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"

log() { printf '[build-ipk] %s\n' "$*"; }
die() { printf '[build-ipk] ERROR: %s\n' "$*" >&2; exit 1; }

command -v ar >/dev/null 2>&1 || die "缺少 ar 命令(binutils)"
command -v tar >/dev/null 2>&1 || die "缺少 tar 命令"
command -v python3 >/dev/null 2>&1 || die "缺少 python3 命令"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$ROOT/$OUTPUT_DIR" ;;
esac
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(CDPATH= cd -- "$OUTPUT_DIR" && pwd)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

if [ -z "$SOURCE_TARBALL" ]; then
  [ -n "$SOURCE_URL" ] || die "必须设置 SOURCE_URL 或 SOURCE_TARBALL"
  SOURCE_TARBALL="$WORK/open-box-linux-x64.tar.gz"
  log "下载上游 x64 Release 资产"
  curl --fail --location --retry 3 --retry-all-errors --output "$SOURCE_TARBALL" "$SOURCE_URL"
fi
[ -f "$SOURCE_TARBALL" ] || die "找不到上游发布包: $SOURCE_TARBALL"

if [ -z "$SOURCE_SHA256_FILE" ] && [ -n "$SOURCE_SHA256_URL" ]; then
  SOURCE_SHA256_FILE="$WORK/open-box-linux-x64.tar.gz.sha256"
  log "下载上游 SHA256 校验文件"
  curl --fail --location --retry 3 --retry-all-errors --output "$SOURCE_SHA256_FILE" "$SOURCE_SHA256_URL"
fi

if [ -n "$SOURCE_SHA256_FILE" ]; then
  [ -f "$SOURCE_SHA256_FILE" ] || die "找不到 SHA256 文件: $SOURCE_SHA256_FILE"
  EXPECTED=$(awk 'NR == 1 { print $1 }' "$SOURCE_SHA256_FILE")
  case "$EXPECTED" in
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*) ;;
    *) die "SHA256 文件格式无效" ;;
  esac
  ACTUAL=$(python3 - "$SOURCE_TARBALL" <<'PY'
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    for block in iter(lambda: f.read(1024 * 1024), b""):
        h.update(block)
print(h.hexdigest())
PY
)
  [ "$(printf '%s' "$EXPECTED" | tr 'A-F' 'a-f')" = "$ACTUAL" ] || die "上游发布包 SHA256 校验失败"
  log "上游 SHA256 校验通过"
else
  log "警告: 未提供 SHA256 文件，仅限本地测试使用"
fi

python3 - "$SOURCE_TARBALL" <<'PY'
import posixpath, sys, tarfile
p = sys.argv[1]
with tarfile.open(p, "r:gz") as tf:
    for m in tf.getmembers():
        name = m.name.replace("\\", "/")
        normalized = posixpath.normpath(name)
        if name.startswith("/") or normalized == ".." or normalized.startswith("../"):
            raise SystemExit(f"unsafe archive path: {m.name}")
        if m.issym() or m.islnk():
            link = m.linkname.replace("\\", "/")
            if link.startswith("/"):
                raise SystemExit(f"unsafe archive link: {m.name} -> {m.linkname}")
            resolved = posixpath.normpath(posixpath.join(posixpath.dirname(normalized), link))
            if resolved == ".." or resolved.startswith("../"):
                raise SystemExit(f"unsafe archive link: {m.name} -> {m.linkname}")
PY

UPSTREAM="$WORK/upstream"
mkdir -p "$UPSTREAM"
tar -xzf "$SOURCE_TARBALL" -C "$UPSTREAM"

[ -f "$UPSTREAM/meta.json" ] || die "上游发布包缺少 meta.json"
VERSION=$(python3 - "$UPSTREAM/meta.json" <<'PY'
import json, re, sys
v = str(json.load(open(sys.argv[1], encoding="utf-8"))["version"])
v = v[1:] if v.startswith("v") else v
v = re.sub(r"[^0-9A-Za-z.+~-]", ".", v).strip(".")
if not v:
    raise SystemExit("invalid version")
print(v)
PY
)

for required in node/bin/node panel/server panel/dist bin/sing-box openwrt/initd/openbox openwrt/initd/openbox-panel; do
  [ -e "$UPSTREAM/$required" ] || die "上游发布包缺少: $required"
done

PKG="$WORK/pkg"
DATA="$PKG/data"
CONTROL="$PKG/control"
mkdir -p "$DATA/opt/open-box" "$DATA/etc/init.d" "$CONTROL"

for item in node panel bin meta.json update.sh uninstall.sh; do
  cp -a "$UPSTREAM/$item" "$DATA/opt/open-box/"
done
cp -a "$UPSTREAM/openwrt/initd/openbox" "$UPSTREAM/openwrt/initd/openbox-panel" "$DATA/etc/init.d/"

if [ -d "$UPSTREAM/openwrt/luci/htdocs" ]; then
  cp -a "$UPSTREAM/openwrt/luci/htdocs/." "$DATA/www/"
fi
if [ -d "$UPSTREAM/openwrt/luci/root" ]; then
  cp -a "$UPSTREAM/openwrt/luci/root/." "$DATA/"
fi

chmod 0755 "$DATA/etc/init.d/openbox" "$DATA/etc/init.d/openbox-panel"
chmod 0755 "$DATA/opt/open-box/node/bin/node" "$DATA/opt/open-box/bin/sing-box"
[ ! -e "$DATA/opt/open-box/data" ] || die "IPK 不得包含用户 data 目录"

INSTALLED_SIZE=$(du -sk "$DATA" | awk '{print $1}')
cat > "$CONTROL/control" <<EOF
Package: $PACKAGE_NAME
Version: $VERSION-$PACKAGE_RELEASE
Architecture: $PACKAGE_ARCH
Maintainer: cmbya <https://github.com/cmbya/ist-Open-Box>
Section: net
Priority: optional
Installed-Size: $INSTALLED_SIZE
Description: Open-Box transparent proxy panel for iStoreOS/OpenWrt x86_64
 This package repackages the official self-contained Open-Box x64 release.
EOF

cat > "$CONTROL/postinst" <<'EOF'
#!/bin/sh
set -e
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
mkdir -p /opt/open-box/data
chmod 0755 /etc/init.d/openbox /etc/init.d/openbox-panel 2>/dev/null || true
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
if [ -x /etc/init.d/rpcd ]; then
  /etc/init.d/rpcd restart >/dev/null 2>&1 || true
fi
/etc/init.d/openbox-panel enable >/dev/null 2>&1 || true
/etc/init.d/openbox-panel restart >/dev/null 2>&1 || /etc/init.d/openbox-panel start >/dev/null 2>&1 || true
exit 0
EOF

cat > "$CONTROL/prerm" <<'EOF'
#!/bin/sh
set -e
if [ "${PKG_UPGRADE:-0}" = "1" ] || [ "${1:-}" = "upgrade" ]; then
  exit 0
fi
if [ -z "${IPKG_INSTROOT:-}" ]; then
  /etc/init.d/openbox stop >/dev/null 2>&1 || true
  /etc/init.d/openbox-panel stop >/dev/null 2>&1 || true
  /etc/init.d/openbox disable >/dev/null 2>&1 || true
  /etc/init.d/openbox-panel disable >/dev/null 2>&1 || true
fi
exit 0
EOF

cat > "$CONTROL/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "${PKG_UPGRADE:-0}" = "1" ] || [ "${1:-}" = "upgrade" ]; then
  exit 0
fi
if [ -z "${IPKG_INSTROOT:-}" ]; then
  rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
  echo "Open-Box 已卸载；用户数据仍保留在 /opt/open-box/data/"
fi
exit 0
EOF
chmod 0755 "$CONTROL/postinst" "$CONTROL/prerm" "$CONTROL/postrm"

printf '2.0\n' > "$PKG/debian-binary"
(
  cd "$CONTROL"
  tar --numeric-owner --owner=0 --group=0 -czf "$PKG/control.tar.gz" control postinst prerm postrm
)
(
  cd "$DATA"
  tar --numeric-owner --owner=0 --group=0 -czf "$PKG/data.tar.gz" .
)

IPK_NAME="${PACKAGE_NAME}_${VERSION}-${PACKAGE_RELEASE}_${PACKAGE_ARCH}.ipk"
rm -f "$OUTPUT_DIR/$IPK_NAME" "$OUTPUT_DIR/$IPK_NAME.sha256"
(
  cd "$PKG"
  ar r "$OUTPUT_DIR/$IPK_NAME" debian-binary control.tar.gz data.tar.gz >/dev/null
)
(
  cd "$OUTPUT_DIR"
  sha256sum "$IPK_NAME" > "$IPK_NAME.sha256"
)

log "完成: $OUTPUT_DIR/$IPK_NAME"
log "$(cat "$OUTPUT_DIR/$IPK_NAME.sha256")"
