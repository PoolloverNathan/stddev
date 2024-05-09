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
      systems ? ["x86_64-linux"],
      extensions ? _: [],
      deps ? _: [],
      devDeps ? pkgs: [pkgs.nix pkgs.git],
      extraShells ? system: pkgs: {},
      packages ? system: pkgs: {},
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
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true; # vscodium serve-web doesn't work
          };
          mkVsCode = vscode:
            pkgs.vscode-with-extensions.override {
              vscode = vscode;
              vscodeExtensions = extensions vscode-extensions.extensions.${system}.open-vsx;
            };
        in {
          devShells.${system}= {
            default = pkgs.mkShell {
              name = "${name}-dev";
              buildInputs = deps pkgs ++ devDeps pkgs;
            };
          } // extraShells system pkgs;
          apps.${system} = {
            ide.type = "app";
            ide.program = "${encase {
                rw.work.${name} = "$origdir";
                rw.tmp = /tmp;
                rw.run = /run;
                ro.nix = /nix;
                ro.dev = /dev;
                ro.etc = /etc;
                wd = /work/${name};
                net = true;
                proc = /proc;
                command = ''
                  HOME=/work/${name}/.vscode/usr/home nix develop -c ${mkVsCode pkgs.vscodium-fhs}/bin/codium --in-process-gpu --disable-software-rasterizer --disable-gpu --no-sandbox -w . --user-data-dir .vscode/usr
                '';
            }}";
            web-ide.type = "app";
            web-ide.program = "${encase {
              rw.work.${name} = "$origdir";
              rw.run = /run;
              ro.nix = /nix;
              ro.inst.vscode = "${mkVsCode pkgs.vscode-fhs}";
              wd = /work/${name};
              net = true;
              proc = /proc;
              tmp = /tmp;
              command = ''
                ${pkgs.tree}/bin/tree / -I nix
                exec /inst/vscode/bin/code serve-web --in-process-gpu --disable-software-rasterizer --disable-gpu --no-sandbox --host 0.0.0.0 --port 2352 --without-connection-token --verbose --user-data-dir .vscode/usr
              '';
            }}";
          };
          formatter.${system} = pkgs.alejandra;
          packages.${system} = packages system pkgs;
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
