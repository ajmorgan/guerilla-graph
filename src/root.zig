const std = @import("std");

pub const utils = @import("utils.zig");
pub const types = @import("types.zig");
pub const format = @import("format.zig");
pub const c_imports = @import("c_imports.zig");
pub const sql_executor = @import("sql_executor.zig");
pub const storage = @import("storage.zig");
pub const task_manager = @import("task_manager.zig");
pub const cli = @import("cli.zig");
pub const help = @import("help/help.zig");
pub const plan_commands = @import("commands/plan.zig");
pub const task_commands = @import("commands/task.zig");
pub const dep_commands = @import("commands/dep.zig");
pub const doctor_commands = @import("commands/doctor.zig");
pub const help_commands = @import("commands/help.zig");
pub const blocked_commands = @import("commands/blocked.zig");
pub const init_commands = @import("commands/init.zig");
pub const workflow_commands = @import("commands/workflow.zig");
pub const list_commands = @import("commands/list.zig");
pub const ready_commands = @import("commands/ready.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(utils);
    std.testing.refAllDecls(types);
    std.testing.refAllDecls(format);
    std.testing.refAllDecls(sql_executor);
    std.testing.refAllDecls(storage);
    std.testing.refAllDecls(task_manager);
    std.testing.refAllDecls(cli);
    std.testing.refAllDecls(help);
    std.testing.refAllDecls(plan_commands);
    std.testing.refAllDecls(task_commands);
    std.testing.refAllDecls(dep_commands);
    std.testing.refAllDecls(doctor_commands);
    std.testing.refAllDecls(help_commands);
    std.testing.refAllDecls(blocked_commands);
    std.testing.refAllDecls(init_commands);
    std.testing.refAllDecls(workflow_commands);
    std.testing.refAllDecls(list_commands);
    std.testing.refAllDecls(ready_commands);
}
