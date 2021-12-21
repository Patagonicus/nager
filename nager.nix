{ config, lib, pkgs, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    concatMapStringsSep
    attrValues
    ;

  ageBin = "${pkgs.age}/bin/age";

  secretOpts = types.submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = ''
          Name of the decrypted secret in /run/nager. Defaults to the name of
          the attribute.
        '';
      };

      file = mkOption {
        type = types.path;
        description = "The source of the secret, as an age encrypted file.";
      };

      mode = mkOption {
        type = types.str;
        default = "0400";
        description = "Permissions for the decrypted secret in a format understood by chmod.";
      };
      owner = mkOption {
        type = types.str;
        default = "0";
        description = "Owner of the decrypted secret.";
      };
      group = mkOption {
        type = types.str;
        default = "0";
        description = "Owning group of the decrypted secret.";
      };
    };
  });

  cfg = config.nager;

  decryptCommands = concatMapStringsSep "\n"
    (secret:
      let
        out = "/run/nager.d/$_nager_generation/${secret.name}";
      in
      ''
        install -m 600 -o root -g root /dev/null "${out}"
        ${ageBin} --decrypt -i "${cfg.keyFile}" "${secret.file}" >"${out}"
      ''
    )
    (attrValues cfg.secrets);

  aclCommands = concatMapStringsSep "\n"
    (secret:
      let
        out = "/run/nager/${secret.name}";
      in
      ''
        chmod "${secret.mode}" "${out}"
        chown "${secret.owner}:${secret.group}" "${out}"
      ''
    )
    (attrValues cfg.secrets);
in
{
  options = {
    nager = {
      keyFile = mkOption {
        type = types.path;
        default = "/etc/nager.age";
        description = "Private key used to decrypt secrets on activation. Must NOT be password protected.";
      };

      secrets = mkOption {
        type = types.attrsOf secretOpts;
        default = { };
        description = "Lists of secrets to be decrypted by nager.";
      };
    };
  };

  config = {
    system.activationScripts = {
      nager = {
        text = ''
          # First part: set up tmpfs if needed, create new directory for secrets.
          _nager_generation="$(basename "$(readlink /run/nager)" || echo 0)"
          (( ++_nager_generation ))

          install -d -m 0751 -o root -g root /run/nager.d
          grep -q "/run/nager.d tmpfs" /proc/mounts || mount -t tmpfs none "/run/nager.d" -o nodev,nosuid,noexec,mode=0751
          install -d -m 0751 -o root -g root "/run/nager.d/$_nager_generation";

          ${decryptCommands}

          chmod 0400 "/run/nager.d/$_nager_generation/"*

          # Finally: replace old generation with new one, delete old generation
          ln -sfn "/run/nager.d/$_nager_generation" /run/nager
          rm -rf "/run/nager.d/$(( _nager_generation - 1 ))";
        '';
        deps = [ "specialfs" ];
      };

      # Set up the secrets (without ACLs) before users are set up. This allows
      # having encrypted password files (but hashedPassword is recommended
      # instead).
      users.deps = [ "nager" ];

      nager-acls = {
        text = aclCommands;
        deps = [ "nager" "users" "groups" ];
      };
    };
  };
}
