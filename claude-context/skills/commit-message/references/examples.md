# Commit message examples

Real messages from the user's repos, sign-off trailers removed (hooks add them).
Ordered from the preferred current style to older ones. Older messages contain
typos and some grammar slips — copy the structure, not the mistakes.

## 1. Bug fix: why, consequence, fix

Three paragraphs: the cause, who it broke and how, what the commit does.

```
mydev-version: Move MYDEV_VERSION_STRING guard out of header

mydev-version.h is installed and pulled in by mydev.h, so the #ifndef guard
fired for every consumer of the library - MYDEV_VERSION_STRING is set by our
own Makefile via -D and cannot exist downstream.

Broke the yocto build of mydev-manager: each file including mydev.h failed with
"#error MYDEV_VERSION_STRING is not defined".

Move the check to src/mydev-version.c, the only translation unit that uses the
macro, and leave the header with just the declaration.
```

## 2. Bug fix with a code line

The failing call on its own indented line — it is the trigger of the bug, which
the diff does not show; the fix itself is never quoted. No separate "fix"
paragraph because the title already says it.

```
main: Fix segfault in display_config()

If mydev_manager_display_config() failed we will call:

  blobmsg_add_json_from_string(&buf, config_json);

with NULL config_json which leads to segfault.
```

## 3. Behaviour change with "Also"

Motivation (a new feature needs it), why it is safe, then a secondary change in
an `Also` paragraph.

```
mydev-manager: Remove clear FOUND_DEVS_XXX_STORAGE at scan start

New Assign IP feature runs several contiguous find device scans and presents
results of all of them to user, so if we clear FOUND_DEVS_XXX_STORAGE at scan
start - we clear previously found devices.

We can safely remove clear of FOUND_DEVS_XXX_STORAGE because there
is a mydev_manager_finish_add_dev() method, that is required to be called
after all scans finished.

Also return -ERR_NO_DEV if device wasn't found in FOUND_DEVS_XXX_STORAGE,
because that matches ERR_NO_DEV meaning.
```

## 4. New feature: user need, then "So introduce"

```
main: Add check_found_dev_password_xxx() RPC calls

User could enter password for device several times, if password isn't correct,
so we need to provide method that will do it fast, without PRG file reading
between calls.

So introduce check_found_dev_password_xxx() RPC calls, that takes PRG file of
device with password from FOUND_DEVS_PASSWORD_PROTECTED_DB_STORAGE and
check user provided password.
```

## 5. Several related defects as a list (trimmed)

Two-space indent, `- `, `;` between items, `.` on the last.

```
database: Fix store and remove records issues, update tests

Several functions had mistakes related to how they handle nodes, that causes
to segfaults and data loss:
  - db_ll_store_data() - didn't update prev_node and next_node if inserting
    was between nodes;
  - db_store_record() - fixed not returning head to origin_head at
    rewrite_record();
  - db_ll_remove_node() - fixed incorrect handling of head->next node.
```

## 6. Reference link

`[1]` in the text, the URL line at the end may exceed the width.

```
unit-tests: Fix expected JSONs after libmydev update

New "UID" field was added in [1] and output order of device-config JSON
parameters from export device config func was changed. So fix tests here.

[1] https://my.gitlab.com/my-packages/libmydev/-/commit/1234567890qwerty
```

## 7. Title only

Self-explanatory changes carry no body.

```
git: Update libmydev submodule
```
```
Makefile: Remove VERSION_SUFFIX for new release
```
```
mydev-manager: Add missing db update in write_parameter_xxx()
```
