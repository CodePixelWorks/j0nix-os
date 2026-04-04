{
  bundlerEnv,
  lib,
  libguestfs,
  makeWrapper,
  qemu,
  runCommand,
  nixpkgsSrc,
  writeText,
  vagrant,
}:
let
  baseVagrant = vagrant.override { withLibvirt = false; };
  ruby = baseVagrant.ruby or baseVagrant.passthru.ruby;
  pluginVersion = "0.12.2";
  emptyGemDir = runCommand "vagrant-libvirt-empty-gemdir" { } ''
    mkdir -p "$out"
  '';
  pluginGems = bundlerEnv {
    pname = "vagrant-libvirt";
    version = pluginVersion;

    inherit ruby;
    gemdir = emptyGemDir;
    gemfile = writeText "Gemfile" "";
    lockfile = writeText "Gemfile.lock" "";
    gemset = import "${nixpkgsSrc}/pkgs/by-name/va/vagrant/gemset_libvirt.nix";

    # Replace gem symlinks with directories so Ruby can resolve the plugin
    # layout consistently under the wrapped Vagrant runtime.
    postBuild = ''
      for gem in "$out"/lib/ruby/gems/*/gems/*; do
        cp -a "$gem/" "$gem.new"
        rm "$gem"
        chmod +w "$gem.new"
        mv "$gem.new" "$gem"
      done
    '';
  };
  baseGemPath = "${baseVagrant.passthru.deps}/lib/ruby/gems/${ruby.version.libDir}";
  pluginGemPath = "${pluginGems}/lib/ruby/gems/${ruby.version.libDir}";
  pluginRuntimePath = lib.makeSearchPath "bin" [
    libguestfs
    qemu
  ];
  pluginMetadata = builtins.toJSON {
    "vagrant-libvirt" = {
      ruby_version = ruby.version;
      vagrant_version = baseVagrant.version;
      gem_version = "";
      require = "";
      sources = [ ];
    };
  };
in
baseVagrant.overrideAttrs (old: {
  pname = "vagrant-with-libvirt";

  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

  postInstall = (old.postInstall or "") + ''
    mkdir -p "$out/vagrant-plugins/plugins.d"
    cat > "$out/vagrant-plugins/plugins.d/vagrant-libvirt.json" <<'EOF'
    ${pluginMetadata}
    EOF

    substituteInPlace "$out/bin/vagrant" \
      --replace-fail "${baseGemPath}" "${baseGemPath}:${pluginGemPath}"

    wrapProgram "$out/bin/vagrant" \
      --prefix PATH : "${pluginRuntimePath}"
  '';

  passthru = (old.passthru or { }) // {
    inherit pluginGems;
  };

  meta = (old.meta or { }) // {
    mainProgram = "vagrant";
  };
})
