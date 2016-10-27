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

  callback-demo =
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
    };

  mktest = name : file : (mkExe {
      name = name;
      dbms = "postgres";

      libraries = {
        inherit callback;
      };

      statements = [
        (rule "safeGet ${name}/main")
        (rule "safeGet ${name}/monitor")
        (rule "safeGet ${name}/cnt")
        (rule "safeGet ${name}/lastline")
        (rule "safeGet ${name}/longrunning")
        (rule "allow env PING")
        (sys "list")
        (sys "char")
        (sys "string")
        (src1 ./test2/Templ.ur)
        (src1 file)
      ];
    });

  tests = [
    (mktest "Simple1" ./test2/Simple1.ur)
    (mktest "Stdout" ./test2/Stdout.ur)
    (mktest "Stress" ./test2/Stress.ur)
  ];

}


