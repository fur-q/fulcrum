local ffi = require "ffi"

ffi.cdef [[
    typedef uint32_t mode_t;
    typedef uint32_t uid_t;
    typedef uint32_t gid_t;
    typedef int32_t  pid_t;

    mode_t umask(mode_t mask);
    int    chdir(const char *path);
    pid_t  fork(void);
    pid_t  getpid(void);
    pid_t  getppid(void);
    uid_t  getuid(void);
    int    setgid(gid_t gid);
    pid_t  setsid(void);
    int    setuid(uid_t uid);
    void*  freopen(const char *path, const char *mode, void *stream);

    struct passwd {
       uid_t   pw_uid;
    };

    struct group {
        gid_t  gr_gid;
    };

    struct passwd* getpwnam(const char *name);
    struct group* getgrnam(const char *name);
]]

local C = ffi.C

local function ensure(check, msg, ...)
  if check then return check end
  if msg then print(string.format(msg, ...)) end
  os.exit(1) 
end

return function(cfg)

    if cfg.daemon then
        if C.getppid() == 1 then return end

        ensure(C.fork() == 0)
        ensure(C.setsid() >= 0, "Error setting session leader")
        ensure(C.chdir("/") >= 0, "Error changing directory")

        C.umask(0)
        
        C.freopen( "/dev/null", "r", io.stdin )
        C.freopen( "/dev/null", "w", io.stdout )
        C.freopen( "/dev/null", "w", io.stderr )
    end

    if cfg.pid then
        local f, err = ensure(io.open(cfg.pid, "w"))
        f:write(C.getpid() .. "\n")
        f:close()
    end

    if cfg.group then
        local gid = ensure(C.getgrnam(cfg.group).gr_gid, "No such group: %s", cfg.group)
        ensure(C.setgid(gid))
    end

    if cfg.user then
        local uid = ensure(C.getpwnam(cfg.user).pw_uid, "No such user: %s", cfg.group)
        ensure(C.setuid(uid))
    end

    ensure(C.getuid() > 0, "Attempting to run as root; quitting")

end