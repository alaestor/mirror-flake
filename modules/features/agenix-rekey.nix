{inputs, self, ...}:{
  config = {

    flake-file.inputs = {
      agenix.url = "github:ryantm/agenix";
      agenix-rekey.url = "github:oddlama/agenix-rekey";
    };

    flake.modules.nixos.secrets-agenix-rekey = {
      imports = [ inputs.agenix-rekey.flakeModule ];
      agenix-rekey = inputs.agenix-rekey.configure {
        userFlake = self;
        nixosConfigurations = self.nixosConfigurations;
        darwinConfigurations = self.darwinConfigurations or { };
      };
    };

  };
}
