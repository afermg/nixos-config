{ ... }:
{
  # Oppy is consumed through homeModules.amunoz-oppy, not a local NixOS host.
  # Its pre-existing system-managed authorized keys remain independent.
  home.file.".ssh/authorized_keys".source = ../ix/id_ed25519_ix_hosts.pub;
}
