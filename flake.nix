# DO-NOT-EDIT. Generated from nucleus declarations.
{
  description = "Alaestor Weissman's personal flake";

  outputs = inputs:
  inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ ./nucleus/flake-module.nix ]
      ++ import ./nucleus/list-modules.nix ./modules;
  }
;

  inputs = {
  agenix = {
    inputs = {
      home-manager = {
        follows = "unstable-home-manager";
      };
      nixpkgs = {
        follows = "unstable-nixpkgs";
      };
    };
    url = "github:ryantm/agenix";
  };
  alpkgs = {
    inputs = {
      nixpkgs = {
        follows = "nixpkgs";
      };
    };
    url = "git+https://codeberg.org/alaestor/pkgs.git";
  };
  android-home-manager = {
    inputs = {
      nixpkgs = {
        follows = "android-nixpkgs";
      };
    };
    url = "github:nix-community/home-manager/release-24.05";
  };
  android-nixpkgs = {
    url = "github:NixOS/nixpkgs/nixos-24.05";
  };
  cryptid-nixpkgs = {
    url = "nixpkgs/4c1018dae018162ec878d42fec712642d214fdfa";
  };
  disko = {
    inputs = {
      nixpkgs = {
        follows = "nixpkgs";
      };
    };
    url = "github:nix-community/disko";
  };
  firefox-extensions-declarative = {
    inputs = {
      nixpkgs = {
        follows = "unstable-nixpkgs";
      };
    };
    url = "github:firefox-extensions-declarative/firefox-extensions-declarative";
  };
  flake-parts = {
    inputs = {
      nixpkgs-lib = {
        follows = "nixpkgs";
      };
    };
    url = "github:hercules-ci/flake-parts";
  };
  impermanence = {
    inputs = {
      home-manager = {
        follows = "";
      };
      nixpkgs = {
        follows = "";
      };
    };
    url = "github:nix-community/impermanence";
  };
  microvm = {
    inputs = {
      nixpkgs = {
        follows = "nixpkgs";
      };
    };
    url = "github:microvm-nix/microvm.nix";
  };
  nix-on-droid = {
    inputs = {
      home-manager = {
        follows = "android-home-manager";
      };
      nixpkgs = {
        follows = "android-nixpkgs";
      };
    };
    url = "github:alaestor/fork-nix-on-droid/better-cross-compile-1";
  };
  nix-wrapper-modules = {
    inputs = {
      nixpkgs = {
        follows = "nixpkgs";
      };
    };
    url = "github:BirdeeHub/nix-wrapper-modules";
  };
  nixpkgs = {
    url = "nixpkgs/nixos-unstable";
  };
  plasma-manager = {
    inputs = {
      home-manager = {
        follows = "unstable-home-manager";
      };
      nixpkgs = {
        follows = "unstable-nixpkgs";
      };
    };
    url = "github:nix-community/plasma-manager";
  };
  stable-home-manager = {
    inputs = {
      nixpkgs = {
        follows = "stable-nixpkgs";
      };
    };
    url = "github:nix-community/home-manager/release-26.05";
  };
  stable-nixpkgs = {
    url = "nixpkgs/nixos-26.05";
  };
  unstable-home-manager = {
    inputs = {
      nixpkgs = {
        follows = "unstable-nixpkgs";
      };
    };
    url = "github:nix-community/home-manager";
  };
  unstable-nixpkgs = {
    follows = "nixpkgs";
  };
  vpn-confinement = {
    url = "github:Maroka-chan/VPN-Confinement";
  };
};
}
