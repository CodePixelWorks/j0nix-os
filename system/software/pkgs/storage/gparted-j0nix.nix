{ bash, gparted, polkit, symlinkJoin, xhost }:

symlinkJoin {
  name = "${gparted.pname}-j0nix-${gparted.version}";
  paths = [ gparted ];

  postBuild = ''
    rm -f "$out/bin/gparted"
    cat >"$out/bin/gparted" <<EOF
#!${bash}/bin/bash
set -eu

orig_gparted=${gparted}/bin/gparted
pkexec_bin=${polkit}/bin/pkexec
xhost_bin=${xhost}/bin/xhost

if [ "\$(id -u)" -eq 0 ]; then
  exec "\$orig_gparted" "\$@"
fi

granted_xhost_root=0
if [ -n "\''${DISPLAY:-}" ] && "\$xhost_bin" >/dev/null 2>&1; then
  if ! "\$xhost_bin" | grep -qi 'SI:localuser:root\$'; then
    "\$xhost_bin" +SI:localuser:root >/dev/null
    granted_xhost_root=1
  fi
fi

"\$pkexec_bin" --disable-internal-agent env \
  DISPLAY="\''${DISPLAY:-}" \
  XAUTHORITY="\''${XAUTHORITY:-}" \
  GDK_BACKEND=x11 \
  WAYLAND_DISPLAY= \
  "\$orig_gparted" "\$@"
status=\$?

if [ "\$granted_xhost_root" -eq 1 ]; then
  "\$xhost_bin" -SI:localuser:root >/dev/null 2>&1 || true
fi

exit "\$status"
EOF
    chmod 755 "$out/bin/gparted"
  '';
}
