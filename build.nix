{ libraries ? {}
, pkgs ? import <nixpkgs> {}
, uwb ? import <urweb-build> {inherit libraries pkgs;}
} :


let

in

with uwb;
rec {

  callback = mkLib {

    name = "Callback";

    statements = [
      (sys "list")
      (ffi ./CallbackFFI.urs)
      (include ./CallbackFFI.h)
      (obj-cpp-11 ./CallbackFFI.cpp)
      (set "safeGet Callback/Default/callback")
      (set "safeGet CallbackNotify/Default/C/callback")
      (src ./Callback.ur ./Callback.urs)
      (src ./CallbackNotify.ur ./CallbackNotify.urs)
      (src ./CallbackNotify2.ur ./CallbackNotify2.urs)
    ];
  };

  tests = [(
    mkExe {
      name = "CallbackDemo";
      dbms = "sqlite";

      libraries = {
        inherit callback;
      };

      statements = [
        (rule "safeGet Demo2/main")
        (rule "safeGet Demo2/monitor")
        (rule "allow env PING")
        (sys "list")
        (sys "char")
        (sys "string")
        (src ./demo/Demo2.ur ./demo/Demo2.urs)
      ];
    }
  )];

}


