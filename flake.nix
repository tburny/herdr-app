{
  description = "Herdr desktop app, from the signed release builds";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # The release workflow writes nix/pins.json after it built and staged a
      # release, then tags that commit: a tag's flake installs its own builds.
      pins = builtins.fromJSON (builtins.readFile ./nix/pins.json);
      systems = builtins.attrNames pins.assets;
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      package =
        {
          lib,
          stdenv,
          stdenvNoCC,
          fetchurl,
          autoPatchelfHook,
          makeDesktopItem,
          copyDesktopItems,
          fontconfig,
          libxcb,
          libxkbcommon,
          libGL,
          vulkan-loader,
          wayland,
        }:
        let
          asset = pins.assets.${stdenvNoCC.hostPlatform.system};
          isLinux = stdenvNoCC.hostPlatform.isLinux;
        in
        stdenvNoCC.mkDerivation {
          pname = "herdr-app";
          inherit (pins) version;

          src = fetchurl {
            url = "https://releases.herdr.dev/app/${pins.version}/${asset.name}";
            inherit (asset) hash;
          };

          sourceRoot = ".";

          nativeBuildInputs = lib.optionals isLinux [
            autoPatchelfHook
            copyDesktopItems
          ];
          # The aarch64 build links fontconfig; the x86_64 build doesn't.
          buildInputs = lib.optionals isLinux [
            stdenv.cc.cc.lib
            fontconfig
            libxcb
            libxkbcommon
          ];
          # wgpu and the Wayland backend load these with dlopen. They go on the
          # RUNPATH, not LD_LIBRARY_PATH: the app starts herdr-core, which
          # passes its environment on to every terminal.
          runtimeDependencies = lib.optionals isLinux [
            libGL
            vulkan-loader
            wayland
          ];

          # The macOS bundle is signed; keep it byte for byte.
          dontFixup = !isLinux;

          desktopItems = lib.optionals isLinux [
            (makeDesktopItem {
              name = "herdr-app";
              desktopName = "Herdr";
              comment = "Terminals and coding agents that keep running";
              exec = "herdr-app";
              icon = "herdr-app";
              terminal = false;
              categories = [ "Development" ];
              startupWMClass = "herdr-app";
            })
          ];

          # The app updates itself only where it finds its release folder (the
          # binary next to herdr-app.svg) or a Herdr.app bundle, so on Linux the
          # icon goes to the icon theme instead.
          installPhase = ''
            runHook preInstall
          ''
          + (
            if isLinux then
              ''
                install -Dm755 herdr-app/herdr-app $out/bin/herdr-app
                install -Dm644 herdr-app/herdr-app.svg $out/share/icons/hicolor/scalable/apps/herdr-app.svg
                install -Dm644 herdr-app/LICENSE herdr-app/THIRD-PARTY-NOTICES -t $out/share/licenses/herdr-app
              ''
            else
              ''
                mkdir -p $out/Applications $out/bin
                cp -R Herdr.app $out/Applications/
                ln -s $out/Applications/Herdr.app/Contents/MacOS/Herdr $out/bin/herdr-app
              ''
          )
          + ''
            runHook postInstall
          '';

          meta = {
            description = "Herdr desktop app, from the signed release builds";
            homepage = "https://github.com/herdrdev/herdr-app";
            license = lib.licenses.asl20;
            platforms = systems;
            mainProgram = "herdr-app";
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
          };
        };
    in
    {
      packages = forAllSystems (pkgs: rec {
        herdr-app = pkgs.callPackage package { };
        default = herdr-app;
      });
      checks = forAllSystems (pkgs: { inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) herdr-app; });
    };
}
