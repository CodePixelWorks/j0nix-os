{
  lib,
  writeText,
  davinci-resolve-studio,
  replaceDependencies,
  ...
}:
let
  # License file content from resolvepatch:
  # https://github.com/unknowntrojan/resolvepatch
  blackmagicLic = writeText "blackmagic.lic" ''
    LICENSE blackmagic davinciresolvestudio 999999 permanent uncounted
      hostid=ANY issuer=ANY customer=ANY issued=14-Aug-2025
      akey=0000-0000-0000-0000-0000 _ck=00 sig="00"
  '';

  nonFhsOriginal = davinci-resolve-studio.passthru.davinci;
  patchedDavinci = nonFhsOriginal.overrideAttrs (old: {
    preFixup = ''
      patch_file="$out/bin/resolve"

      # ---- License file (resolvepatch approach) ----
      mkdir -p "$out/.license"
      cp ${blackmagicLic} "$out/.license/blackmagic.lic"
      echo "resolve-patch: wrote blackmagic.lic license file"

      # ---- Binary patching (acuifex patterns) ----
      try_patch() {
        local pattern="$1" offset="$2" patch_byte="$3" label="$4"
        local matches
        matches=$(LANG=C grep -obUaP "$pattern" "$patch_file" 2>/dev/null) || true
        local matchcount
        matchcount=$(echo "$matches" | grep -c . 2>/dev/null || echo 0)

        if [[ -z "$matches" ]]; then
          echo "resolve-patch [$label]: no match found"
          return 1
        elif [[ "$matchcount" -ne 1 ]]; then
          echo "resolve-patch [$label]: $matchcount matches, skipping"
          return 1
        fi

        local patternOffset
        patternOffset=$(echo "$matches" | cut -d: -f1)
        local instructionOffset=$((patternOffset + offset))
        echo "resolve-patch [$label]: patching at offset $instructionOffset"
        echo -en "$patch_byte" | dd conv=notrunc of="$patch_file" bs=1 seek=$instructionOffset count=1 2>/dev/null
        return 0
      }

      # Try patterns newest-first; stop at first success.
      # Patterns from: https://acuifex.ru/blog/cracking-davinci-resolve-studio-license/
      # 20.3+ (patch byte: 0x75)
      if try_patch \
        '\xff\xe9\x75\x02\x00\x00\x85\xdb\x74\x68\x4d\x8b\x7e\x10\x49\x89' \
        8 '\x75' "20.3+"; then
        echo "resolve-patch: successfully patched (20.3+ pattern)"
      # 19.0b4 - 20.0+ (patch byte: 0x85)
      elif try_patch \
        '\x55\x41\x57\x41\x56\x53\x48\x83\xec.\x49\x89\xfe\xc7\x47\x34\xff\xff\xff\xff\x85\xf6\x0f\x84....\x89\xf5\x81\xfe\x13\xfc\xff\xff\x0f\x85' \
        23 '\x85' "19.0b4-20.0+"; then
        echo "resolve-patch: successfully patched (19.0b4-20.0+ pattern)"
      # 18.x - 18.6.6+ (patch byte: 0x85)
      elif try_patch \
        '\x55\x41\x56\x53\x48\x83\xec\x20\x49\x89\xfe\x85\xf6\x0f\x84....\x81\xfe\x13\xfc\xff\xff\x0f\x85' \
        14 '\x85' "18.x"; then
        echo "resolve-patch: successfully patched (18.x pattern)"
      else
        echo "resolve-patch: WARNING - no binary pattern matched for version $(cat $out/bin/resolve 2>/dev/null | head -c 100 || echo unknown)"
        echo "resolve-patch: Relying on license file + RLM_LICENSE only"
      fi
    '';
  });
in
replaceDependencies {
  drv = davinci-resolve-studio;
  replacements = [
    {
      oldDependency = nonFhsOriginal;
      newDependency = patchedDavinci;
    }
  ];
}
