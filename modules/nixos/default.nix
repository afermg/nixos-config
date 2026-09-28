{
  inputs,
  outputs,
}:
{
  arm-emulation = import ./arm-emulation.nix;
  ejabberd-tailscale = import ./ejabberd-tailscale.nix;
  # sunshine = import ./sunshine.nix;
  # nvidia-vgpu = import ./nvidia-vgpu inputs;
}
