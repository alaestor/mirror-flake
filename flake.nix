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
      nixpkgs = {
        follows = "unstable-nixpkgs";
      };
    };
    url = "github:ryantm/agenix";
  };
  alpkgs = {
    inputs = {
      flake-parts = {
        follows = "flake-parts";
      };
      nixpkgs = {
        follows = "nixpkgs";
      };
    };
    url = "git+https://git.0x04.cc/alaestor/pkgs.git";
  };
  android-home-manager = {
    inputs = {
      nixpkgs = {
        follows = "android-nixpkgs";
      };
    };
    url = "github:nix-community/home-manager/release-26.05";
  };
  android-nixpkgs = {
    url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";
  };
  cryptid-nixpkgs = {
    url = "nixpkgs/4c1018dae018162ec878d42fec712642d214fdfa";
  };
  deepseek-harness = {
    inputs = {
      flake-parts = {
        follows = "flake-parts";
      };
      nixpkgs = {
        follows = "nixpkgs";
      };
    };
    url = "github:Moraxyc/deepseek-harness.nix";
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
      flake-parts = {
        follows = "flake-parts";
      };
      nixpkgs = {
        follows = "unstable-nixpkgs";
      };
    };
    url = "git+https://git.0x04.cc/alaestor/mirror-firefox-extensions-declarative";
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
    url = "git+https://git.0x04.cc/alaestor/fork-nix-on-droid.git?ref=better-cross-compile-1";
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
    url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
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
    url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";
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
    url = "git+https://git.0x04.cc/alaestor/mirror-VPN-Confinement";
  };
  zed-cea = {
    inputs = {
      nixpkgs = {
        follows = "nixpkgs";
      };
    };
    url = "git+https://git.0x04.cc/alaestor/zed-cea.git";
  };
};
}
