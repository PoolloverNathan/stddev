{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };
  outputs = {
    self,
    nixpkgs,
    vscode-extensions,
    flake-parts,
  }: let
    main = {
      name,
      port ? 2352,
      systems ? ["x86_64-linux"],
      extensions ? _: [],
      nixpkgsConfig ? {},
      overlays ? [],
      deps ? _: [],
      devDeps ? pkgs: [pkgs.nix pkgs.git],
      extraShells ? system: pkgs: {},
      packages ? system: pkgs: {},
      patches ? {},
      functor ? builtins.throw "flake ${name} cannot be invoked",
    }:
      builtins.foldl'
      nixpkgs.lib.attrsets.recursiveUpdate
      {}
      (builtins.map
        (system: let
          encase = args:
            import ./encase.nix ({
                name = "${name}-encase";
                inherit system pkgs;
              }
              // args);
          pkgs = import ((import nixpkgs {
            inherit system;
          }).applyPatches {
            name = "nixpkgs-patched-${name}";
            src = nixpkgs;
            patches = patches.nixpkgs or [./vscode-serve-web.patch];
            patchFlags = ["-t" "-p1"];
          }) {
            inherit system overlays;
            config = { allowUnfree = true; } // nixpkgsConfig; # vscodium serve-web doesn't work
          };
          mkVsCode = vscode:
            pkgs.vscode-with-extensions.override {
              vscode = vscode;
              vscodeExtensions = extensions vscode-extensions.extensions.${system}.open-vsx;
            };
        in {
          devShells.${system} = {
            default = pkgs.mkShell {
              name = "${name}-dev";
              buildInputs = deps pkgs ++ devDeps pkgs;
            };
          } // extraShells system pkgs;
          apps.${system} = {
            ide.type = "app";
            ide.program = "${encase {
              rw.work.${name} = "$origdir";
              rw.run = /run;
              ro.nix = /nix;
              ro.dev = /dev;
              ro.etc = /etc;
              wd = /work/${name};
              net = true;
              proc = /proc;
              tmp = /tmp;
              command = ''
                TMPDIR=/tmp HOME=/tmp/home exec nix develop path:. -c ${mkVsCode pkgs.vscodium-fhs}/bin/codium --in-process-gpu --disable-software-rasterizer --disable-gpu --no-sandbox -w . --user-data-dir /tmp/vscode
              '';
            }}";
            web-ide.type = "app";
            web-ide.program = "${encase {
              rw.work.${name} = "$origdir";
              rw.run = /run;
              ro.nix = /nix;
              ro.dev = /dev;
              ro.etc = /etc;
              wd = /work/${name};
              net = true;
              proc = /proc;
              tmp = /tmp;
              command = ''
                TMPDIR=/tmp HOME=/tmp/home exec nix develop path:. -c ${mkVsCode pkgs.vscode-fhs}/bin/code serve-web --host 0.0.0.0 --port ${toString port} --without-connection-token --verbose --user-data-dir /tmp/vscode
              '';
            }}";
          };
          formatter.${system} = pkgs.alejandra;
          packages.${system} = packages system pkgs;
          __functor = self: functor;
        })
        systems);
  in
    main {
      name = "stddev";
      devDeps = pkgs: [pkgs.nix pkgs.nil pkgs.git];
      extensions = exts: [exts.jnoortheen.nix-ide];
      packages = system: pkgs: {
        default = pkgs.writeShellScriptBin "stddev" ''
          ${pkgs.cowsay}/bin/cowsay "The environment is working!"
        '';
      };
    }
    // {
      __functor = this: main;
    };
}
