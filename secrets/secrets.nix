let
  # personal_key = "ssh-rsa AAAA....";
  personal_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKdcdlNS1SO+rJHjRQWd33qvqBEZcZR8ypTQUeC9LZ4";
  moby_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIClOuXVukvwqgE+UDxJShus+JGprTC8QIoc1G/Ege5KK";
  oppy_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINCW3CZ4r7VhI7+4rC+oOE4n3AMXEy3F2vm8jjHeTClR";
  keys = [
    personal_key
    moby_key
  ];
in
{
  "sshkey_personal.age".publicKeys = keys;
  "tailscale.age".publicKeys = keys;
  "atuin.age".publicKeys = keys;
  "cloudflared-overleaf.age".publicKeys = keys;
  "cloudflared-marimohub.age".publicKeys = keys;
  "cloudflared-marimohub-quasimorphic.age".publicKeys = keys;
  "marimohub-google.age".publicKeys = keys;
  "netrc-overleaf.age".publicKeys = keys;
  "org-gcal.age".publicKeys = keys;
  "hedgedoc-env.age".publicKeys = keys;
  "pi-msg.age".publicKeys = keys;
  "hindsight-api-token.age".publicKeys = keys;
  "pi-msg-oppy.age".publicKeys = [
    personal_key
    oppy_key
  ];
}
