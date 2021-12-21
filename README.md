# nager

Secret management for NixOS using [age](https://github.com/FiloSottile/age).

## What

If you naively put something like

```
{
  # Bad, don't do this!
  services.openssh.hostKeys = [ ./ssh_host_ed25519_key ];
  …
}
```

Then `./ssh_host_ed25519_key` will be added to the nix store, which is world readable, meaning that any user on the machine can now impersonate your SSH server. With `nager`, you can instead encrypt the file with `age` before adding it to the Nix store. That way, only the encrypted file is exposed to other users, which is useless to them (if you keep your age secret key secret).

```
/* Create a secret key for decryption:

   $ sudo install -m 0600 /dev/null /etc/nager.age
   $ age-keygen | sudo tee /etc/nager.age >/dev/null
   $ sudo chmod 0400 /etc/nager.age

   age-keygen will tell you the public key for the secret key you generated.
   Something like `age1zvk…`, which you'll need later.
 */
{
  # Note: path is quoted, so it doesn't get added to the nix store.
  # nager will create this file on system activation.
  services.openssh.hostKeys = [ "/run/nager/ssh_host_ed25519_key" ];

  # Note: path is unquoted, we want the .age file to be added to the store.
  # Create the encrypted file with
  # `age --encrypt --recipient age1zvk… ssh_host_ed25519_key >ssh_host_ed25519_key.age`
  nager.files.ssh_host_ed25519_key = ./ssh_host_ed25519_key.age;

  …
}
```

Note: It is recommended to encrypt your secrets to multiple recipients and/or keep other backups of them and the secret keys. You're responsible yourself for avoid data loss.

## Importing

### Flakes

Currently, only flake based installation is officially supported. If you have a flake based NixOS system, use something like this:

```
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nager = {
      url = "github:patagonicus/nager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nager, ... }: {
    nixosConfigurations.foo = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        nager.nixosModule
      ];
    };
  };
}
```

You'll likely want to add `pkgs.age` to your `environment.systemPackages` to be able to encrypt secrets. However, this is not needed for decrypting them as `nager` will pull it in automatically.

### Non-Flakes

If you're not using flakes, something like this *might* work, but this is untested. Do let me know if you're running into trouble - if I know someone without flakes wants to use this module, I'll spend some time making it work.

```
{ config, lib, pkgs, ... }:
let
  nager = builtins.fetchGit {
    url = "https://github.com/patagonicus/nager";
    rev = "a2295d01273d6adef1a9276d770f67eda06a4a37";
    refs = "refs/heads/main";
  };
in {
  imports = [
    "${nager}/nager.nix"
  ];
}
```

You'll likely want to add `pkgs.age` to your `environment.systemPackages` to be able to encrypt secrets. However, this is not needed for decrypting them as `nager` will pull it in automatically.

## Configuration

Configuration looks something like this:

```
{
  nager = {
    # Path to the secret key used for decrypting the secrets.
    keyFile = "/etc/nager.age";

    secrets = {
      # Decrypt ./vpn.wg.age and make it available as /run/nager/vpn.wg.
      # It will be owned by root:root and have 0400 permissions.
      vpn.wg = ./vpn.wg.age;
      application-key = {
        # The source file. When using the attrSet format, this is the only
        # required option.
        file = ./application.age;

        # Make this one available as `/run/nager/application key` (with a space).
        # You could also use `"application key" = { … }` for the same effect.
        name = "application key";

        # This key will be owner and group readable and owned by user `foo` and group `bar`.
        mode = "0440";
        user = "foo";
        group = "bar";
      };
    };
  };
}
```

## Comparison with agenix

[`agenix`](https://github.com/ryantm/agenix) is the project that inspired `nager` in the first place. `nager` was written since I wanted something simpler than `agenix` that does not rely on SSH host keys for decrypting the secrets (AFAIK, `agenix` can also be used with non-SSH-host-keys).

A quick comparison of features:

* `agenix` supports arbitrary targets for decrypted secrets, `nager` makes all of them available in `/run/nager/`.
* `agenix` provides a wrapper around `age` for editing and rekeying secrets.
* `agenix` has about three times as many lines of Nix code compared to `nager`¹.

¹ Measured via `find . -iname '*example*' -prune -o -iname '*.nix' -exec wc -l '{}' +` at 57806bf7e340f4cae705c91748d4fdf8519293a9 for `agenix` and a2295d01273d6adef1a9276d770f67eda06a4a37 for `nager`. This includes empty lines and comments, but I think it still shows that `nager` is simpler than `agenix`.

## Name

`nager` is a mix of `nix` and `age` (with an extra `r` thrown in), which turns it into the German word for rodent, ["(der) Nager"](https://en.wiktionary.org/wiki/Nager). It is pronounced `[ˈnaːɡɐ]`.
