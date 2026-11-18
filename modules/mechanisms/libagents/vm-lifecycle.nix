/** User-manager scopes and serialized idle shutdown for the fixed shared VM. */
{ self, ... }:
{
  flake.lib.agents.mkVmLifecycle =
    pkgs:
    { name, hostUser, sshHostPort, knownHosts, lingerSeconds, readyTimeoutSeconds }:
    let
      lib = pkgs.lib;
      script = self.data.path "agents/vm/lifecycle.sh";
      settings = {
        AGENT_VM_NAME = name;
        AGENT_VM_USER = hostUser;
        AGENT_VM_PORT = toString sshHostPort;
        AGENT_VM_KNOWN_HOSTS = toString knownHosts;
        AGENT_VM_LINGER = toString lingerSeconds;
        AGENT_VM_READY_TIMEOUT = toString readyTimeoutSeconds;
      };
      make = executable: operation: extra: pkgs.writeShellApplication {
        name = executable;
        runtimeInputs = [ pkgs.coreutils pkgs.util-linux pkgs.systemd pkgs.openssh ];
        text = lib.concatStringsSep "\n" (lib.mapAttrsToList
          (key: value: "export ${key}=${lib.escapeShellArg value}") settings)
          + "\n${extra}\nexec ${pkgs.bash}/bin/bash ${script} ${operation} \"$@\"";
      };
      inner = make "agent-vm-session-inner" "acquire" "";
    in
    {
      session = make "agent-vm-session" "session"
        "export AGENT_VM_INNER=${lib.escapeShellArg (lib.getExe inner)}";
      monitor = make "agent-vm-lifecycle" "monitor" "";
      stop = make "agent-vm-stop" "stop" "";
      restart = make "agent-vm-restart" "restart" "";
    };
}
