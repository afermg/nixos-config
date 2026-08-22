# ARCHIVED CONFIGURATION — retained with ./overleaf.nix for recovery only.
# The active package definition is linked from ./OVERLEAF_ARCHIVE.md.
{
  lib,
  stdenv,
  fetchFromGitHub,
  maven,
  jdk21_headless,
  makeWrapper,
}:

let
  src = fetchFromGitHub {
    owner = "yu-i-i";
    repo = "overleaf-cep";
    rev = "f82dc82212e671c1950404d38688752f392c0740";
    hash = "sha256-g88mDT3xQ3I1TxHfn8hsjH78yAoouPN2evwH/IrvSwA=";
  };
in
maven.buildMavenPackage {
  pname = "overleaf-git-bridge";
  version = "0-unstable-2026-04-13";

  inherit src;
  sourceRoot = "${src.name}/services/git-bridge";

  # nixpkgs' Maven 3.9.16 resolves newer default lifecycle plugins than the
  # overleaf-nix package was hashed with. Keep this local override until the
  # corrected dependency hash is available from overleaf-nix itself.
  mvnHash = "sha256-n/Ad4ZpZetisd3aXEZzYHfxrv2ysjHbXk9ffgyUT6xk=";
  mvnParameters = "-Dmaven.test.skip=true package";

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/git-bridge"
    cp target/writelatex-git-bridge*-jar-with-dependencies.jar \
      "$out/share/git-bridge/git-bridge.jar"

    makeWrapper ${jdk21_headless}/bin/java "$out/bin/overleaf-git-bridge" \
      --add-flags "-jar $out/share/git-bridge/git-bridge.jar"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Overleaf git bridge (Java) for the CEP fork";
    homepage = "https://github.com/yu-i-i/overleaf-cep";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
  };
}
