import base64
import fcntl
import json
import os
import stat
import sys


def main() -> int:
    if len(sys.argv) not in (6, 7):
        return 64

    mode = sys.argv[1]
    path = os.path.abspath(sys.argv[2])
    backup_path = os.path.abspath(sys.argv[3])
    try:
        max_bytes = int(sys.argv[4])
        revision = int(sys.argv[5])
    except ValueError:
        return 64
    if max_bytes < 0 or revision < 0 or mode not in ("commit", "delete"):
        return 64

    state_dir = os.path.dirname(path)
    lock_path = os.path.join(state_dir, ".state.lock")
    pending = os.path.join(state_dir, f".{os.path.basename(path)}.{os.getpid()}.tmp")
    backup_pending = os.path.join(
        state_dir, f".{os.path.basename(backup_path)}.{os.getpid()}.tmp"
    )
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW
    try:
        lock_descriptor = os.open(
            lock_path,
            os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW,
            0o600,
        )
        with os.fdopen(lock_descriptor, "rb+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)

            current_data = b""
            current_revision = -1
            try:
                current_descriptor = os.open(
                    path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW
                )
                if not stat.S_ISREG(os.fstat(current_descriptor).st_mode):
                    os.close(current_descriptor)
                    raise OSError("state is not a regular file")
                with os.fdopen(current_descriptor, "rb") as current:
                    current_data = current.read(max_bytes + 1)
            except FileNotFoundError:
                pass
            except OSError:
                return 22
            try:
                current_value = json.loads(current_data)
                current_revision = int(current_value.get("storageRevision", 0))
            except (ValueError, TypeError, UnicodeDecodeError, json.JSONDecodeError):
                pass

            if revision < current_revision:
                return 0

            if mode == "delete":
                value = {
                    "schemaVersion": 1,
                    "storageRevision": revision,
                    "nextNewIndex": 0,
                    "cards": {},
                    "lastNotificationDate": "",
                    "panelSession": {
                        "tipId": "", "answerRevealed": False,
                        "cursorTarget": "", "preferredRating": "again",
                        "confirmationAction": "", "confirmationOrigin": ""
                    }
                }
                data = json.dumps(value, separators=(",", ":")).encode() + b"\n"
            else:
                if len(sys.argv) != 7:
                    return 64
                try:
                    data = base64.b64decode(sys.argv[6], validate=True)
                    value = json.loads(data)
                except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
                    return 21
                if (not isinstance(value, dict)
                        or int(value.get("storageRevision", -1)) != revision):
                    return 21

            if not data.endswith(b"\n") or len(data) > max_bytes:
                return 20

            if mode == "commit" and current_data and current_revision >= 0:
                _write_atomic(backup_pending, backup_path, current_data, flags)
            elif mode == "delete":
                try:
                    os.unlink(backup_path)
                except FileNotFoundError:
                    pass

            _write_atomic(pending, path, data, flags)
            directory = os.open(state_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        return 0
    except OSError:
        return 22
    finally:
        for temporary in (pending, backup_pending):
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def _write_atomic(pending: str, destination: str, data: bytes, flags: int) -> None:
    descriptor = os.open(pending, flags, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(pending, destination)


if __name__ == "__main__":
    raise SystemExit(main())
