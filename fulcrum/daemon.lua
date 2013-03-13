local ffi = require "ffi"

ffi.cdef[[
    typedef uint32_t mode_t;
    typedef uint32_t uid_t;
    typedef uint32_t gid_t;
    typedef int32_t  pid_t;
    typedef int32_t  time_t;

    char *strerror(int errnum);

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
        char *pw_name;
        char *pw_passwd;
        uid_t pw_uid;
        gid_t pw_gid;
        time_t pw_change;
        char *pw_class;
        char *pw_gecos;
        char *pw_dir;
        char *pw_shell;
        time_t pw_expire;
    };

    struct group {
        char *gr_name;
        char *gr_passwd;
        gid_t gr_gid;
        char **gr_mem;
    };

    struct passwd* getpwnam(const char *name);
    struct group* getgrnam(const char *name);

    int prctl(int option, const char* arg2, unsigned long arg3, unsigned long arg4, unsigned long arg5);
    int setproctitle(const char *fmt, ...);
]]

local C, PR_SET_NAME  = ffi.C, 15
local dm = {}

-- this doesn't work in ps on linux, the only way around it is to
-- overwrite argv[0] which doesn't seem possible without some real C
-- it does work in top though!
function dm.setproctitle(title)
    -- ++ check for some more OSs here
    if ffi.os == "Linux" then
        ffi.C.prctl(PR_SET_NAME, ffi.new("const char *", title), 0, 0, 0)
    elseif ffi.os == "BSD" then
        ffi.C.setproctitle("%s", title)
    end
end

function dm.daemonise()
    if C.getppid() == 1 then return nil, "Already session leader" end

    local pid = C.fork()
    if pid == -1 then
        return nil, "fork() failed (%s)" % ffi.string(C.strerror(ffi.errno()))
    elseif pid > 0 then
        os.exit(0)
    end

    if C.setsid() == 0 then return nil, "Error setting session leader" end
    if C.chdir("/") == 0 then return nil, "Error changing working directory" end

    C.umask(0)

    C.freopen( "/dev/null", "r", io.stdin )
    C.freopen( "/dev/null", "w", io.stdout )
    C.freopen( "/dev/null", "w", io.stderr )
end

function dm.writepid(path)
    local f, err = io.open(path, "w")
    if not f then return nil, err end
    f:write(C.getpid() .. "\n")
    f:close()
end

function dm.setgroup(group)
    local gid = type(group) == "number" and group or C.getgrnam(group).gr_gid
    if not gid then return nil, "No such group: %s" % group end
    if C.setgid(gid) == -1 then
        return nil, "Error setting group: %s (%s)" % {
            group, ffi.string(C.strerror(ffi.errno()))
        }
    end
    return true
end

function dm.setuser(user)
    local uid = type(user) == "number" and user or C.getpwnam(user).pw_uid
    if not uid then return nil, "No such user: %s" % user end
    if C.setuid(uid) == -1 then
        return nil, "Error setting user: %s (%s)" % {
            user, ffi.string(C.strerror(ffi.errno()))
        }
    end
    return true
end

function dm.is_root()
    return C.getuid() == 0
end

return dm