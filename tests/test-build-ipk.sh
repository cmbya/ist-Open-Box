#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

UPSTREAM="$TMP/upstream"
mkdir -p \
  "$UPSTREAM/node/bin" \
  "$UPSTREAM/panel/server" \
  "$UPSTREAM/panel/dist" \
  "$UPSTREAM/bin" \
  "$UPSTREAM/openwrt/initd" \
  "$UPSTREAM/openwrt/luci/htdocs/luci-static/resources/view/openbox" \
  "$UPSTREAM/openwrt/luci/root/usr/share/luci/menu.d" \
  "$UPSTREAM/openwrt/luci/root/usr/share/rpcd/acl.d"

printf '#!/bin/sh\n' > "$UPSTREAM/node/bin/node"
printf 'console.log("open-box")\n' > "$UPSTREAM/panel/server/index.mjs"
printf '<html>open-box</html>\n' > "$UPSTREAM/panel/dist/index.html"
printf '#!/bin/sh\n' > "$UPSTREAM/bin/sing-box"
printf '#!/bin/sh /etc/rc.common\n' > "$UPSTREAM/openwrt/initd/openbox"
printf '#!/bin/sh /etc/rc.common\n' > "$UPSTREAM/openwrt/initd/openbox-panel"
printf 'view\n' > "$UPSTREAM/openwrt/luci/htdocs/luci-static/resources/view/openbox/status.js"
printf '{}\n' > "$UPSTREAM/openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json"
printf '{}\n' > "$UPSTREAM/openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json"
printf '{"version":"v9.8.7","arch":"x64"}\n' > "$UPSTREAM/meta.json"
printf '#!/bin/sh\n' > "$UPSTREAM/update.sh"
printf '#!/bin/sh\n' > "$UPSTREAM/uninstall.sh"
chmod +x "$UPSTREAM/node/bin/node" "$UPSTREAM/bin/sing-box"

tar -C "$UPSTREAM" -czf "$TMP/open-box-linux-x64.tar.gz" .

OUT="$TMP/out"
SOURCE_TARBALL="$TMP/open-box-linux-x64.tar.gz" \
  SOURCE_SHA256_FILE="" \
  OUTPUT_DIR="$OUT" \
  "$ROOT/scripts/build-ipk.sh"

IPK=$(find "$OUT" -maxdepth 1 -name 'open-box_*_x86_64.ipk' -print -quit)
[ -n "$IPK" ] || { echo 'IPK was not created' >&2; exit 1; }

EXTRACT="$TMP/extract"
mkdir -p "$EXTRACT"
(cd "$EXTRACT" && tar -xzf "$IPK")
[ "$(cat "$EXTRACT/debian-binary")" = "2.0" ]

tar -xzf "$EXTRACT/control.tar.gz" -C "$EXTRACT"
grep -q '^Package: open-box$' "$EXTRACT/control"
grep -q '^Version: 9.8.7-1$' "$EXTRACT/control"
grep -q '^Architecture: x86_64$' "$EXTRACT/control"
grep -q '^Installed-Size: [1-9][0-9]*$' "$EXTRACT/control"
[ -x "$EXTRACT/postinst" ]
[ -x "$EXTRACT/prerm" ]
[ -x "$EXTRACT/postrm" ]

tar -xzf "$EXTRACT/data.tar.gz" -C "$EXTRACT"
[ -x "$EXTRACT/opt/open-box/node/bin/node" ]
[ -x "$EXTRACT/opt/open-box/bin/sing-box" ]
[ -f "$EXTRACT/opt/open-box/panel/server/index.mjs" ]
[ -f "$EXTRACT/etc/init.d/openbox-panel" ]
[ -f "$EXTRACT/www/luci-static/resources/view/openbox/status.js" ]
[ -f "$EXTRACT/usr/share/luci/menu.d/luci-app-openbox.json" ]
[ -f "$EXTRACT/usr/share/rpcd/acl.d/luci-app-openbox.json" ]
[ ! -e "$EXTRACT/opt/open-box/data" ]

printf 'test-build-ipk: PASS\n'
