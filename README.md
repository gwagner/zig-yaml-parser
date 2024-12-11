# Zig YAML Parser

This project is a bit of a playground to get a better understanding of how to use Zig's reflection system.

Feel free to fork and open issues but I am not promising that anything will get fixed.

## How to use


First run: `zig fetch --save=yaml-parser https://github.com/gwagner/zig-yaml-parser/archive/refs/heads/main.zip`

> You can also re-run this command to pull down the freshest version of the repo

Next, in your build.zig add the following:

```
const yaml_parser = b.dependency("yaml-parser", .{});
exe.root_module.addImport("yaml", &yaml_parser.artifact("yaml-parser").root_module);
```

> exe should be the name of whatever your binary build step is

Finally, you need to have [libyaml](https://github.com/yaml/libyaml) installed.  I am not going to provide instructions for that since it is different on all systems.  

Run your build and profit!
