{
  flake.modules.homeManager.discord =
    { config, pkgs, ... }:
    {
      home.packages = [ pkgs.webcord ];

      xdg.configFile."WebCord/_config.json" = {
        # Copy config into place so WebCord can update its mutable runtime copy.
        onChange =
          let
            dir = "${config.xdg.configHome}/WebCord";
          in
          ''
            rm -f ${dir}/config.json
            cp ${dir}/_config.json ${dir}/config.json
            chmod u+w ${dir}/config.json
          '';

        text = builtins.toJSON {
          settings.advanced.redirection.warn = false;
          settings.general.menuBar.hide = true;
          settings.general.window.hideOnClose = false;

          settings.privacy.permissions = {
            audio = true;
            display-capture = true;
            fullscreen = true;
            notifications = true;
            video = true;
          };

          # Required for compatibility with features such as Krisp.
          settings.advanced.csp.enabled = false;
        };
      };
    };
}
