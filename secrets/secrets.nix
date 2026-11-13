let
  # personal_key = "ssh-rsa AAAA....";
  personal_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKdcdlNS1SO+rJHjRQWd33qvqBEZcZR8ypTQUeC9LZ4";
  moby_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIClOuXVukvwqgE+UDxJShus+JGprTC8QIoc1G/Ege5KK";
  ix_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICbdw/pGo2apLsXS8l9ArrL8FhJ8zTYBDQPs9HokthgE";
  ix_host_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKY0holJSH6l/MeBPRWgzITfAVwT7dJESRBTP0pHjQA7";
  oppy_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINCW3CZ4r7VhI7+4rC+oOE4n3AMXEy3F2vm8jjHeTClR";
  keys = [
    personal_key
    moby_key
  ];
in
{
  "blocky-private.yaml.age".publicKeys = [
    personal_key
    ix_host_key
  ];
  "sshkey_personal.age".publicKeys = keys;
  "tailscale.age".publicKeys = keys;
  "atuin.age".publicKeys = keys ++ [ ix_key ];
  # Same sync key, encrypted for Spirit's existing local agenix identity and
  # the existing personal recovery identity. No fleet SSH private-key copying.
  "atuin-spirit.age".publicKeys = [
    personal_key
    "age13fxnk3v6au9j2nvhuquzjam75nawndy7raltrqznxpfra509uu5swmyahw"
  ];
  "cloudflared-overleaf.age".publicKeys = keys;
  "cloudflared-marimohub.age".publicKeys = keys;
  "cloudflared-marimohub-quasimorphic.age".publicKeys = keys;
  "marimohub-google.age".publicKeys = keys;
  "netrc-overleaf.age".publicKeys = keys;
  "org-gcal.age".publicKeys = keys;
  "hedgedoc-env.age".publicKeys = keys;
  "pi-msg.age".publicKeys = keys;
  "pi-msg-ix.age".publicKeys = [
    personal_key
    ix_key
  ];
  "pi-msg-moby-ix.age".publicKeys = keys;
  "hindsight-api-token.age".publicKeys = keys;
  "pi-msg-oppy.age".publicKeys = [
    personal_key
    oppy_key
  ];
  "pi-msg-oppy-ix.age".publicKeys = [
    personal_key
    oppy_key
  ];
}
