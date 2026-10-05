"""Log in using rbw without putting the password/key in process arguments."""

import getpass
import subprocess
import sys

import pexpect


def main():
    subprocess.run(["rbw", "unlock"], check=True)
    username = subprocess.check_output(
        ["rbw", "get", "atuin", "--field", "username"], text=True
    ).strip()
    password = subprocess.check_output(["rbw", "get", "atuin"], text=True).rstrip("\n")
    if not username or not password:
        raise RuntimeError("The rbw atuin entry must contain a username and password")

    # Invalidated server sessions otherwise make `atuin login` say it is already
    # logged in. Logout only clears authentication; it does not delete history.
    subprocess.run(["atuin", "logout"], check=True)
    child = pexpect.spawn(
        "atuin",
        ["login", "--username", username, "--key", ""],
        encoding="utf-8",
        echo=False,
        timeout=120,
    )
    try:
        while True:
            event = child.expect_exact(
                ["Please enter password: ", "Please enter two-factor code: ", pexpect.EOF]
            )
            if event == 0:
                child.sendline(password)
                password = ""
            elif event == 1:
                child.sendline(getpass.getpass("Atuin two-factor code: "))
            else:
                break
        child.close()
        if child.exitstatus != 0:
            raise RuntimeError("Atuin login failed; check the account and managed key")
    finally:
        if child.isalive():
            child.terminate(force=True)

    subprocess.run(["atuin", "sync"], check=True)
    subprocess.run(["atuin", "status"], check=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, pexpect.ExceptionPexpect):
        # Do not print pexpect's buffers or exceptions: they may contain input.
        print("Atuin login/sync failed; check rbw, connectivity, and the shared key.", file=sys.stderr)
        sys.exit(1)
