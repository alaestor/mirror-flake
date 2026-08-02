/**
  Enables CUPS, a PDF printer, and the configured Brother HL-L2320D printer.
*/
{
  flake.modules.nixos.printers = # TODO: less generic name; this is very specific...
    { pkgs, ... }:
    {
      services.printing = {
        enable = true;
        startWhenNeeded = true;
        drivers = [ pkgs.brlaser ];
        cups-pdf = {
          enable = true;
          instances.pdf.settings.Out = "\${HOME}/Downloads";
        };
      };

      hardware.printers.ensurePrinters = [
        {
          name = "HL-L2320D-series";
          deviceUri = "usb://Brother/HL-L2320D%20series?serial=U63877L4N584614";
          model = "drv:///brlaser.drv/brl2320d.ppd";
          ppdOptions = {
            PageSize = "A4";
            brlaserEconomode = "True";
          };
        }
      ];
    };
}
