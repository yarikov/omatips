import errno
import os
import stat
import sys


def main() -> int:
    if len(sys.argv) != 3:
        return 64

    path = sys.argv[1]
    try:
        max_bytes = int(sys.argv[2])
    except ValueError:
        return 64
    if max_bytes < 0:
        return 64

    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
    try:
        descriptor = os.open(path, flags)
    except FileNotFoundError:
        return 10
    except OSError as error:
        return 11 if error.errno in (errno.ELOOP, errno.ENXIO) else 12

    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            return 11

        remaining = max_bytes + 1
        while remaining > 0:
            chunk = os.read(descriptor, min(65536, remaining))
            if not chunk:
                break
            sys.stdout.buffer.write(chunk)
            remaining -= len(chunk)
        sys.stdout.buffer.flush()
        return 0
    except OSError:
        return 12
    finally:
        os.close(descriptor)


if __name__ == "__main__":
    raise SystemExit(main())
