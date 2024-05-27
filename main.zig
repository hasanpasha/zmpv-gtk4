const std = @import("std");
const gtk = @import("gtk");

const core = gtk.core;
const Application = gtk.Application;
const ApplicationWindow = gtk.ApplicationWindow;
const Widget = gtk.Widget;
const GLArea = gtk.GLArea;
const Window = gtk.Window;
const GApplication = core.Application;
const gdk = gtk.Gdk;
const GLContext = gdk.GLContext;

const epoxy = @cImport({
    @cInclude("epoxy/gl.h");
    @cInclude("epoxy/glx.h");
});
const C = @cImport({
    @cInclude("locale.h");
});

const zmpv = @import("zmpv");
const Mpv  = zmpv.Mpv;
const MpvRenderContext = zmpv.MpvRenderContext;
const MpvRenderParam = MpvRenderContext.MpvRenderParam;

fn get_process_address(ctx: ?*anyopaque, name: [*c]const u8) ?*anyopaque {
    _ = ctx;
    const func = epoxy.glXGetProcAddress(name);
    return @ptrCast(@constCast(func));
}

fn render(glarea: *GLArea) bool {
    glarea.queueRender();
    return false;
}

fn mpv_render_update_callback(glarea_ptr_op: ?*anyopaque) void {
    if (glarea_ptr_op) |glarea_ptr| {
        const glarea: *GLArea = @ptrCast(@alignCast(glarea_ptr));
        _ = gtk.GLib.idleAdd(gtk.GLib.PRIORITY_HIGH, render, .{glarea});
    }
}

fn play_video(glarea: *GLArea, mpv_ptr: *Mpv) void {
    _ = glarea;
    var cmd_args = [_][]const u8{"loadfile", "sample.mp4"};
    mpv_ptr.command_async(0, &cmd_args) catch |err| {
        std.log.err("failed to play video: {}", .{err});
    };
}

fn on_realize(glarea: *GLArea, mpv_ptr: *Mpv, ctx_ptr: *MpvRenderContext) void {
    glarea.makeCurrent();

    var params = [_]MpvRenderParam{
        .{ .ApiType = .OpenGL },
        .{ .OpenglInitParams =  .{
            .get_process_address = &get_process_address,
            .get_process_address_ctx = null,
        } },
    };
    ctx_ptr.* = MpvRenderContext.create(mpv_ptr.*, &params) catch {
        return;
    };

    ctx_ptr.*.set_update_callback(&mpv_render_update_callback, glarea);
}

fn on_unrealize(glarea: *GLArea, mpv_ptr: *Mpv, ctx_ptr: *MpvRenderContext) void {
    _ = glarea;
    ctx_ptr.free();
    mpv_ptr.terminate_destroy();
    std.heap.c_allocator.destroy(ctx_ptr);
    std.heap.c_allocator.destroy(mpv_ptr);
}

fn on_resize(glarea: *GLArea) void {
    _ = gtk.GLib.idleAdd(gtk.GLib.PRIORITY_HIGH, render, .{glarea});
}

fn on_render(glarea: *GLArea, context: *GLContext, ctx_ptr: *MpvRenderContext) bool {
    _ = context;

    if (!ctx_ptr.update()) {
        return false;
    }

    var as_widget = glarea.into(Widget);
    const scale = as_widget.getScaleFactor();
    const rect_width = as_widget.getAllocatedWidth();
    const rect_height = as_widget.getAllocatedHeight();
    var fbo: c_int = undefined;
    epoxy.glGetIntegerv(epoxy.GL_FRAMEBUFFER_BINDING, @ptrCast(&fbo));


    var render_params = [_]MpvRenderParam{
        .{ .OpenglFbo = .{
            .fbo = fbo,
            .w = rect_width * scale,
            .h = rect_height * scale,
            .internal_format = 0,
        } },
        .{ .FlipY = true },
    };
    ctx_ptr.render(&render_params) catch {
        std.log.err("failed to render", .{});
        return false;
    };

    return true;
}

fn wakeup(mpv_ptr_op: ?*anyopaque) void {
    if (mpv_ptr_op) |mpv_ptr_anon| {
        const mpv_ptr: *Mpv = @ptrCast(@alignCast(mpv_ptr_anon)) ;
        while (true) {
            const event = mpv_ptr.wait_event(0) catch {return;};
            defer event.free();
            switch (event.event_id) {
                .None => break,
                .LogMessage => {
                    const log = event.data.LogMessage;
                    std.debug.print("[{s}]: {s} \"{s\"}", .{log.level, log.prefix, log.text});
                },
                else => {}
            }
        }
    }

}

fn setup_mpv(mpv_ptr: *Mpv) !void {
    _ = C.setlocale(C.LC_NUMERIC, "C");
    mpv_ptr.* = try zmpv.Mpv.create(std.heap.c_allocator, null);
    try mpv_ptr.*.initialize();
    mpv_ptr.*.set_wakeup_callback(&wakeup, mpv_ptr);
    try mpv_ptr.*.request_log_messages(.Info);
}

pub fn activate(arg_app: *GApplication) void {
    const app = arg_app.tryInto(Application).?;
    var appwindow = ApplicationWindow.new(app);
    var window = appwindow.into(gtk.Window);
    window.setTitle("mpv - gtk4");
    window.setDefaultSize(800, 600);
    window.setResizable(true);

    var glarea = GLArea.new();

    const mpv_ptr = std.heap.c_allocator.create(Mpv) catch {
        return;
    };
    const ctx_ptr = std.heap.c_allocator.create(MpvRenderContext) catch {
        return;
    };

    setup_mpv(mpv_ptr) catch |err| {
        std.log.err("error setting up mpv: {}", .{err});
    };

    _ = glarea.connectRender(on_render, .{ctx_ptr}, .{});
    _ = glarea.connect("realize", on_realize, .{mpv_ptr, ctx_ptr}, .{}, &[_]type{void, *GLArea});
    _ = glarea.connect("realize", play_video, .{mpv_ptr}, .{}, &[_]type{void, *GLArea});
    _ = glarea.connect("unrealize", on_unrealize, .{mpv_ptr, ctx_ptr}, .{}, &[_]type{void, *GLArea});
    _ = glarea.connectResize(on_resize, .{}, .{});

    window.setChild(glarea.into(Widget));

    window.present();
}

pub fn main() u8 {
    var app = Application.new("me.hasanpasha.zmpv_gtk4_simple", .{});
    defer app.__call("unref", .{});
    _ = app.connect("activate", activate, .{}, .{}, &.{void, *GApplication});
    return @intCast(app.__call("run", .{std.os.argv}));
}
