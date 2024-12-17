# Zig YAML Parser

This project is a bit of a playground to get a better understanding of how to use Zig's reflection system.

For more information, you can checkout the project [here](https://www.valewood.org/i-wrote-a-zig-yaml-parser/)

Feel free to fork and open issues but I am not promising that anything will get fixed.

**This is very much MVP to suit my specific use case.**

## Why Did I Make this?

Simple... JSON is way too much typing.

I have done a fair amount of GoLang in my career which has led me to using the `go generate` pattern quite a bit.  I would love to use the same pattern in Zig, but i dont want to define everything in JSON just to satisfy the stdlib.

Would JSON have been easier?  Probably.

## How to use

**This requires a build of Zig 0.14.  Current stable 0.13.x will not work due to changes in the typing system for @typeInfo()**

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
