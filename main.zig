const std = @import("std");

pub fn main() void {
    // TODO - look up how to buffer reads/writes & acquire/release mutexes for these streams
    const stdIn = std.io.getStdIn().reader();
    const stdOut = std.io.getStdOut().writer();
    const stdErr = std.io.getStdErr().writer();
    runRepl(stdIn.any(), stdOut.any(), stdErr.any());
    stdErr.print("Exiting gracefully\n", .{}) catch {};
}

fn runRepl(
    reader: std.io.AnyReader,
    writer: std.io.AnyWriter,
    err_writer: std.io.AnyWriter,
) void {
    var running = true;
    var buf: [1024]u8 = undefined;
    while (running) {
        const maybe_line = reader.readUntilDelimiterOrEof(&buf, '\n') catch fatal(err_writer);
        if (maybe_line) |line| {
            // imagine we're building up a valid s-expression and evaluating it
            writer.print("You said \"{s}\"\n", .{line}) catch fatal(err_writer);
            if (std.mem.eql(u8, line, "#exit")) {
                running = false;
            }
        }
    }
}

fn fatal(err_writer: std.io.AnyWriter) noreturn {
    err_writer.print("Sorry, something went wrong\n", .{}) catch {};
    std.process.exit(1);
}
