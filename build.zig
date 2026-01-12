const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.


    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("guerilla_graph", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
        .optimize = optimize,
        // Link C library for SQLite integration
        .link_libc = true,
    });

    // Link system SQLite3 library
    // This provides the raw C API that we'll use via @cImport(@cInclude("sqlite3.h"))
    mod.linkSystemLibrary("sqlite3", .{});

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "gg",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // Link C library for SQLite integration
            .link_libc = true,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "guerilla_graph" is the name you will use in your source code to
                // import this module (e.g. `@import("guerilla_graph")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "guerilla_graph", .module = mod },
            },
        }),
    });

    // Link system SQLite3 library for executable
    exe.root_module.linkSystemLibrary("sqlite3", .{});

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the relative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Separate test files (tests/ directory)
    const separate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/all.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "guerilla_graph", .module = mod },
            },
        }),
    });
    separate_tests.root_module.linkSystemLibrary("sqlite3", .{});

    const run_separate_tests = b.addRunArtifact(separate_tests);
    test_step.dependOn(&run_separate_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.

    // Code formatting step. This checks that all source files are properly
    // formatted according to Zig's style guide. Run `zig build fmt` to check
    // or `zig fmt .` to automatically fix formatting issues.
    const fmt_step = b.step("fmt", "Run zig fmt on all source files");
    const fmt = b.addFmt(.{
        .paths = &.{
            "src",
            "tests",
            "build.zig",
            "build.zig.zon",
        },
        .check = true, // Check mode: fail if any files need formatting
    });
    fmt_step.dependOn(&fmt.step);

    // Compile-time validation step. This performs a full compilation check
    // without generating executable code, making it much faster than a full
    // build. Useful for CI pipelines and quick validation during development.
    // Run `zig build check` to validate code compiles correctly.
    const check_step = b.step("check", "Check if code compiles without building artifacts");
    const check = b.addExecutable(.{
        .name = "gg",
        .root_module = exe.root_module,
    });
    check_step.dependOn(&check.step);

    // Documentation generation step. This creates HTML documentation from
    // doc comments in the source code. The generated docs will be placed
    // in zig-out/doc/. Run `zig build docs` to generate documentation.
    const docs_step = b.step("docs", "Generate documentation");
    const docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "doc",
    });
    docs_step.dependOn(&docs.step);

    // Convenience step to run all quality checks: formatting, compilation, and tests.
    // This is ideal for running before committing code or in CI pipelines.
    // Run `zig build ci` to execute all checks.
    const ci_step = b.step("ci", "Run all quality checks (fmt, check, test)");
    ci_step.dependOn(fmt_step);
    ci_step.dependOn(check_step);
    ci_step.dependOn(test_step);

    // Release installation step. Builds with ReleaseFast optimization regardless
    // of -Doptimize flag. Use with --prefix (-p) to install to a custom location.
    // Examples:
    //   zig build install-release -p ~/.local     # Installs to ~/.local/bin/gg
    //   zig build install-release -p /usr/local   # Installs to /usr/local/bin/gg
    const install_release_step = b.step("install-release", "Install ReleaseFast build (use -p PREFIX to set install location)");

    // Create a separate ReleaseFast executable for the install-release step
    const release_exe = b.addExecutable(.{
        .name = "gg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseFast, // Always ReleaseFast regardless of -Doptimize
            .link_libc = true,
            .imports = &.{
                .{ .name = "guerilla_graph", .module = mod },
            },
        }),
    });
    release_exe.root_module.linkSystemLibrary("sqlite3", .{});

    const install_release = b.addInstallArtifact(release_exe, .{});
    install_release_step.dependOn(&install_release.step);
}
