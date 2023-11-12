rockspec_format = "3.0"
package = "luabench"
version = "scm-1"
source = {
   url = "git+https://github.com/moonlibs/luabench"
}
description = {
   summary = "Tool for benchmark testings",
   detailed = "luabench is cli tool to provide unified interface for benchmark unit-testing",
   homepage = "https://github.com/moonlibs/luabench",
   license = "MIT"
}
dependencies = {
   "lua ~> 5.1",
   "tarantool",
}
build = {
   type = "builtin",
   install = {
      bin = {
         luabench = "luabench.lua"
      },
   },
   modules = {
      luabench = "luabench.lua"
   }
}
