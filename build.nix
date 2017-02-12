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
      (src1 ./Callback.ur)
    ];
  };

  callback-demo =
    mkExe {
      name = "CallbackDemo";
      dbms = "sqlite";

      libraries = {
        inherit callback;
      };

      statements = [
        (rule "safeGet Callback1/main")
        (rule "allow env PING")
        (sys "list")
        (sys "char")
        (sys "string")
        (src ./demo/Callback1.ur ./demo/Callback1.urs)
      ];
    };

}


