//! A pseudo-terminal and the program running on it, with libc calls only. All the `unsafe` of the console is in this file.
//!
//! The program gets the slave side as its standard input, output and error, its own session and the slave as its controlling terminal,
//! so Ctrl-C and window changes reach it. Dropping a `PtyProcess` ends the program and reaps it: SIGHUP to its process group,
//! SIGKILL after a short grace, then `wait`, so no zombie stays behind on any exit path.
use super::frames::Size;
use std::fs::{File, OpenOptions};
use std::io::{self, Read};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

/// How long a program gets to leave after SIGHUP before it is killed.
pub const HANGUP_GRACE: Duration = Duration::from_secs(2);
const EXIT_POLL: Duration = Duration::from_millis(20);
/// The standard input of the child is the slave side, so this is the file number the controlling terminal is claimed on.
const CHILD_TTY_FD: RawFd = 0;

pub struct PtyProcess {
    child: Child,
    master: File,
}

impl PtyProcess {
    /// Starts `program` with `arguments` on a new pty of the given size. Nothing goes through a shell.
    pub fn spawn(program: &str, arguments: &[String], size: Size) -> io::Result<PtyProcess> {
        let (master, slave) = open_pair()?;
        set_size(slave.as_raw_fd(), size)?;
        let child = start(program, arguments, slave)?;
        Ok(PtyProcess { child, master: File::from(master) })
    }

    /// Another handle on the master side, for a thread that reads the output.
    pub fn reader(&self) -> io::Result<File> {
        self.master.try_clone()
    }

    /// Another handle on the master side, for a thread that writes the keystrokes.
    pub fn writer(&self) -> io::Result<File> {
        self.master.try_clone()
    }

    pub fn resize(&self, size: Size) -> io::Result<()> {
        set_size(self.master.as_raw_fd(), size)
    }

    #[cfg(test)]
    pub fn pid(&self) -> u32 {
        self.child.id()
    }

    fn signal_group(&self, signal: libc::c_int) {
        let result = unsafe { libc::killpg(self.child.id() as libc::pid_t, signal) };
        let error = io::Error::last_os_error();
        if result != 0 && error.raw_os_error() != Some(libc::ESRCH) {
            eprintln!("console: could not signal the process group: {error}");
        }
    }

    /// SIGHUP, a grace period, SIGKILL, then reap the program.
    fn end(&mut self) {
        self.signal_group(libc::SIGHUP);
        let deadline = Instant::now() + HANGUP_GRACE;
        while Instant::now() < deadline && matches!(self.child.try_wait(), Ok(None)) {
            std::thread::sleep(EXIT_POLL);
        }
        self.signal_group(libc::SIGKILL);
        if let Err(error) = self.child.wait() {
            eprintln!("console: could not wait for the program: {error}");
        }
    }
}

impl Drop for PtyProcess {
    fn drop(&mut self) {
        self.end();
    }
}

/// Reads output. A closed pty (the program and everything it started are gone) ends the stream: Linux reports it as EIO, others as 0 bytes.
pub fn read_output(from: &mut File, buffer: &mut [u8]) -> io::Result<usize> {
    match from.read(buffer) {
        Err(error) if error.raw_os_error() == Some(libc::EIO) => Ok(0),
        other => other,
    }
}

fn start(program: &str, arguments: &[String], slave: OwnedFd) -> io::Result<Child> {
    let mut command = Command::new(program);
    command.args(arguments).stdin(Stdio::from(slave.try_clone()?)).stdout(Stdio::from(slave.try_clone()?)).stderr(Stdio::from(slave));
    unsafe {
        command.pre_exec(|| {
            if libc::setsid() == -1 {
                return Err(io::Error::last_os_error());
            }
            check(libc::ioctl(CHILD_TTY_FD, libc::TIOCSCTTY as _, 0))
        });
    }
    command.spawn()
}

fn check(result: libc::c_int) -> io::Result<()> {
    if result == -1 { Err(io::Error::last_os_error()) } else { Ok(()) }
}

fn open_pair() -> io::Result<(OwnedFd, OwnedFd)> {
    let raw = unsafe { libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY) };
    check(raw)?;
    let master = unsafe { OwnedFd::from_raw_fd(raw) };
    check(unsafe { libc::fcntl(raw, libc::F_SETFD, libc::FD_CLOEXEC) })?;
    check(unsafe { libc::grantpt(raw) })?;
    check(unsafe { libc::unlockpt(raw) })?;
    let name = slave_name(raw)?;
    let slave = OpenOptions::new().read(true).write(true).custom_flags(libc::O_NOCTTY | libc::O_CLOEXEC).open(name)?;
    Ok((master, OwnedFd::from(slave)))
}

#[cfg(target_os = "linux")]
fn slave_name(master: RawFd) -> io::Result<String> {
    const NAME_BYTES: usize = 128;
    let mut buffer = [0 as libc::c_char; NAME_BYTES];
    let code = unsafe { libc::ptsname_r(master, buffer.as_mut_ptr(), NAME_BYTES) };
    if code != 0 {
        return Err(io::Error::from_raw_os_error(code));
    }
    let name = unsafe { std::ffi::CStr::from_ptr(buffer.as_ptr()) };
    Ok(name.to_string_lossy().into_owned())
}

/// Development machines that are not Linux only have the older call, which is not thread-safe; tests that use it hold this lock.
#[cfg(not(target_os = "linux"))]
fn slave_name(master: RawFd) -> io::Result<String> {
    static GUARD: std::sync::Mutex<()> = std::sync::Mutex::new(());
    let _held = GUARD.lock().map_err(|_| io::Error::other("the pty name lock was poisoned"))?;
    let pointer = unsafe { libc::ptsname(master) };
    if pointer.is_null() {
        return Err(io::Error::last_os_error());
    }
    Ok(unsafe { std::ffi::CStr::from_ptr(pointer) }.to_string_lossy().into_owned())
}

fn set_size(fd: RawFd, size: Size) -> io::Result<()> {
    let window = libc::winsize { ws_row: size.rows, ws_col: size.cols, ws_xpixel: 0, ws_ypixel: 0 };
    check(unsafe { libc::ioctl(fd, libc::TIOCSWINSZ as _, &window) })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::console::frames::START_SIZE;
    use std::io::Write;

    fn read_until(from: &mut File, wanted: &str) -> String {
        let (mut seen, mut buffer) = (String::new(), [0u8; 4096]);
        while !seen.contains(wanted) {
            match read_output(from, &mut buffer) {
                Ok(0) | Err(_) => break,
                Ok(n) => seen.push_str(&String::from_utf8_lossy(&buffer[..n])),
            }
        }
        seen
    }

    fn alive(pid: u32) -> bool {
        unsafe { libc::kill(pid as libc::pid_t, 0) == 0 }
    }

    #[test]
    fn what_is_typed_comes_back_through_the_pty() {
        let process = PtyProcess::spawn("/bin/cat", &[], START_SIZE).unwrap();
        let (mut reader, mut writer) = (process.reader().unwrap(), process.writer().unwrap());
        writer.write_all(b"hello pty\n").unwrap();
        assert!(read_until(&mut reader, "hello pty").contains("hello pty"));
    }

    #[test]
    fn the_program_sees_the_start_size_and_every_resize() {
        let process = PtyProcess::spawn("/bin/sh", &["-c".into(), "stty size; read ignored; stty size".into()], Size { cols: 100, rows: 30 }).unwrap();
        let (mut reader, mut writer) = (process.reader().unwrap(), process.writer().unwrap());
        assert!(read_until(&mut reader, "30 100").contains("30 100"));
        process.resize(Size { cols: 200, rows: 50 }).unwrap();
        writer.write_all(b"\n").unwrap();
        assert!(read_until(&mut reader, "50 200").contains("50 200"));
    }

    #[test]
    fn dropping_ends_a_program_that_ignores_nothing_and_leaves_no_zombie() {
        let process = PtyProcess::spawn("/bin/sleep", &["60".into()], START_SIZE).unwrap();
        let pid = process.pid();
        assert!(alive(pid));
        drop(process);
        assert!(!alive(pid), "the program is gone and was reaped");
    }

    #[test]
    fn a_program_that_ignores_hangup_is_killed_after_the_grace_period() {
        let process = PtyProcess::spawn("/bin/sh", &["-c".into(), "trap '' HUP; while :; do sleep 1; done".into()], START_SIZE).unwrap();
        let (pid, started) = (process.pid(), Instant::now());
        std::thread::sleep(Duration::from_millis(200));
        drop(process);
        assert!(started.elapsed() >= HANGUP_GRACE, "it was given the grace period first");
        assert!(!alive(pid));
    }

    #[test]
    fn a_program_that_cannot_start_is_an_error_not_a_panic() {
        assert!(PtyProcess::spawn("/nonexistent/program", &[], START_SIZE).is_err());
    }
}
