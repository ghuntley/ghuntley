# integration-tests

Demo at https://asciinema.org/a/359317

```shell
$ nix-build .
```

Tests can be run interactively, which is particularly useful when developing or debugging a test:

```shell
$ nix-build . -A driver
./result/bin/nixos-test-driver
starting VDE switch for network 1
```

After whcih any statement can be used, such as:

```python
start_all()
test_script()
machine.succeed("touch /tmp/foo")
print(machine.succeed("pwd")) # Show stdout of command
```

# testing primitives

```start```:
Start the virtual machine. This method is asynchronous  it does not wait for the machine to finish booting.

```shutdown```:
Shut down the machine, waiting for the VM to exit.

```crash```:
Simulate a sudden power failure, by telling the VM to exit immediately.

```block```:
Simulate unplugging the Ethernet cable that connects the machine to the other machines.

```unblock```:
Undo the effect of block.

```screenshot```:
Take a picture of the display of the virtual machine, in PNG format. The screenshot is linked from the HTML log.

```get_screen_text```:
Return a textual representation of what is currently visible on the machine's screen using optical character recognition.

Note: This requires passing `enableOCR` to the test attribute set.

```send_monitor_command```:
Send a command to the QEMU monitor. This is rarely used, but allows doing stuff such as attaching virtual USB disks to a running machine.

```send_keys```:
Simulate pressing keys on the virtual keyboard, e.g., `send_keys("ctrl-alt-delete")`.

```send_chars```:
Simulate typing a sequence of characters on the virtual keyboard, e.g., `send_keys("foobar\n")` will type the string `foobar` followed by the `Enter` key.

```execute```:
Execute a shell command, returning a list (status, stdout).

```succeed```:
Execute a shell command, raising an exception if the exit status is not zero, otherwise returning the standard output.

```fail```:
Like succeed, but raising an exception if the command returns a zero status.

```wait_until_succeeds```:
Repeat a shell command with 1-second intervals until it succeeds.

```wait_until_fails```:
Repeat a shell command with 1-second intervals until it fails.

```wait_for_unit```:
Wait until the specified systemd unit has reached the active state.

```wait_for_file```:
Wait until the specified file exists.

```wait_for_open_port```:
Wait until a process is listening on the given TCP port (on localhost, at least).

```wait_for_closed_port```:
Wait until nobody is listening on the given TCP port.

```wait_for_x```:
Wait until the X11 server is accepting connections.

```wait_for_text```:
Wait until the supplied regular expressions matches the textual contents of the screen by using optical character recognition (see `get_screen_text`).

Note: This requires passing `enableOCR` to the test attribute set.

```wait_for_window```:
Wait until an X11 window has appeared whose name matches the given regular expression, e.g., `wait_for_window("Terminal")`.

```copy_file_from_host```:
Copies a file from host to machine, e.g., `copy_file_from_host("myfile", "/etc/my/important/file").`

The first argument is the file on the host. The file needs to be accessible while building the nix derivation. The second argument is the location of the file on the machine.

```systemctl```:
Runs systemctl commands with optional support for `systemctl --user`

```
machine.systemctl("list-jobs --no-pager") # runs `systemctl list-jobs --no-pager`
machine.systemctl("list-jobs --no-pager", "any-user") # spawns a shell for `any-user` and runs `systemctl --user list-jobs --no-pager`
```

To test user units declared by systemd.user.services the optional user argument can be used:

```
machine.start()
machine.wait_for_x()
machine.wait_for_unit("xautolock.service", "x-session-user")
```

# recommended reading

- https://github.com/NixOS/nixpkgs/blob/2147c3c34bbcdad64064f0236820653cd49f4bbc/nixos/lib/test-driver/test-driver.py
- https://nixos.org/manual/nixos/stable/#sec-writing-nixos-tests
- https://nixos.org/manual/nixos/stable/#sec-running-nixos-tests-interactively
