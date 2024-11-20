{
  description = "Toffee";

 inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      overlays = [];
      pkgs = import nixpkgs {
        inherit system overlays;
      };
      llvm = pkgs.llvmPackages_18;
      stdenv = llvm.libcxxStdenv;
    in
    with pkgs; pkgs.mkShell.override { stdenv = stdenv; } {
      devShells.default = mkShell rec {
        buildInputs = with pkgs; [
          ripgrep cmake-language-server
          llvm.clang-tools
          pkg-config cmake ninja codespell
          lldb

          zig zls

          cargo rustc
          llvm.libcxx llvm.clang-tools llvm.clangUseLLVM llvm_18 llvm.libclang

          libGL

          vulkan-loader

          wayland wayland-scanner egl-wayland

          xorg.libX11 xorg.libXext
          xorg.libXcursor xorg.libXrandr xorg.libXi
          libxkbcommon

          yq jq
        ];

        packages = buildInputs;

        /*shellHook = ''
          export LIBCLANG_PATH=${llvm.libclang.lib}/lib
          export LD_LIBRARY_PATH=${pkgs.wayland}/lib:$LD_LIBRARY_PATH
        '';*/

        LD_LIBRARY_PATH = "${lib.makeLibraryPath buildInputs}";

        shellHook = ''
          export LIBCLANG_PATH=${llvm.libclang.lib}/lib
          export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.wayland}/lib:${pkgs.libxkbcommon}/lib
        '';
      };
    }
  );
}

