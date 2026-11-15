# reads a colcon workspace's package.xml files at eval time (needs --impure) and maps
# their rosdep keys to nix packages. package.xml stays the only place deps are declared
{ lib, pkgs, ros, skip }:
src:
let
  systemKeys = lib.importJSON ../deps/system-keys.json;
  teamKeys = removeAttrs (lib.importJSON ../deps/team-keys.json) [ "_comment" "_notes" ];

  ignored = [ "COLCON_IGNORE" "AMENT_IGNORE" "CATKIN_IGNORE" ];
  noWalk = [ "build" "install" "log" "node_modules" "__pycache__" ];

  # same as colcon: stop at the first package.xml, skip ignored dirs
  walk = dir:
    let ents = builtins.readDir dir; in
    if lib.any (n: ents ? ${n}) ignored then [ ]
    else if ents ? "package.xml" then [ "${dir}/package.xml" ]
    else lib.concatMap (n: walk "${dir}/${n}")
      (lib.attrNames (lib.filterAttrs (n: t: t == "directory" && !(lib.hasPrefix "." n) && !(lib.elem n noWalk)) ents));

  # strip comments first, a commented out dep isn't a dep
  parse = file:
    let
      xml = lib.concatStrings (lib.filter lib.isString (builtins.split "<!--([^-]|-[^-])*-->" (builtins.readFile file)));
      deps = builtins.split "<(depend|build_depend|build_export_depend|buildtool_depend|buildtool_export_depend|exec_depend|test_depend)[^>]*>([^<]+)</" xml;
      name = builtins.match ".*<name>[[:space:]]*([^<[:space:]]+)[[:space:]]*</name>.*" (builtins.replaceStrings [ "\n" ] [ " " ] xml);
    in {
      name = if name == null then throw "uwrt_nix: no <name> in ${file}" else lib.head name;
      deps = lib.unique (lib.concatMap (m: if lib.isList m then [ (lib.trim (lib.elemAt m 1)) ] else [ ]) deps);
    };

  packages = map parse (walk src);
  names = map (p: p.name) packages;
  built = lib.filter (p: !(lib.elem p.name skip)) packages;

  attr = path:
    let p = lib.splitString "." path; in
    lib.attrByPath p (lib.attrByPath p null pkgs) ros;

  resolve = pkg: key:
    let
      dashed = builtins.replaceStrings [ "_" ] [ "-" ] key;
      # team keys can be { linux = [ ]; darwin = [ ]; } when a dep only exists on one
      entry = teamKeys.${key} or systemKeys.${key} or null;
      paths = if lib.isAttrs entry
        then entry.${if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux"} or [ ]
        else entry;
    in
    if lib.elem key names then { ok = [ ]; }
    else if paths != null then
      let missing = lib.filter (a: attr a == null) paths; in
      if missing == [ ] then { ok = map attr paths; }
      else { bad = "${pkg}: ${key} -> ${lib.concatStringsSep " " missing} (not in nixpkgs)"; }
    else if ros ? ${dashed} then { ok = [ ros.${dashed} ]; }
    else { bad = "${pkg}: ${key}"; };

  results = lib.concatMap (p: map (resolve p.name) p.deps) built;
  bad = lib.unique (lib.concatMap (r: lib.optional (r ? bad) r.bad) results);
in
if bad != [ ] then
  throw ''
    uwrt_nix: unknown rosdep keys in ${src}:
      ${lib.concatStringsSep "\n  " bad}
    add the key to deps/team-keys.json, or run `uwrt deps update` if rosdistro gained it''
else {
  inherit names;
  skipped = lib.intersectLists skip names;
  deps = lib.unique (lib.concatMap (r: r.ok) results);
}
