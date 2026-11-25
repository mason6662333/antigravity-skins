#include "pipe.h"
#include <unistd.h>
#include <spawn.h>
#include <fcntl.h>
#include <poll.h>
#include <string.h>
#include <stdlib.h>
#include <libproc.h>
#include <sys/stat.h>
extern char **environ;

pid_t start_skin_host(const char *binary, int *send_fd, int *receive_fd) {
    int input[2], output[2];
    if (pipe(input) != 0) return -1;
    if (pipe(output) != 0) { close(input[0]); close(input[1]); return -1; }
    // Keep the source descriptors distinct from Chromium's fixed descriptors 3 and 4.
    int r = fcntl(input[0], F_DUPFD_CLOEXEC, 10);
    int w = fcntl(output[1], F_DUPFD_CLOEXEC, 10);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    int ends[] = {input[0], input[1], output[0], output[1]};
    for (int i = 0; i < 4; ++i) posix_spawn_file_actions_addclose(&actions, ends[i]);
    posix_spawn_file_actions_adddup2(&actions, r, 3);
    posix_spawn_file_actions_adddup2(&actions, w, 4);
    posix_spawn_file_actions_addclose(&actions, r);
    posix_spawn_file_actions_addclose(&actions, w);
    char *const args[] = {(char *)binary, "--remote-debugging-pipe", NULL};
    pid_t child = -1;
    if (r >= 0 && w >= 0) {
        if (posix_spawn(&child, binary, &actions, NULL, args, environ) != 0) child = -1;
    }
    posix_spawn_file_actions_destroy(&actions);
    close(r); close(w); close(input[0]); close(output[1]);
    if (child < 0) { close(input[1]); close(output[0]); }
    else { *send_fd = input[1]; *receive_fd = output[0]; }
    return child;
}

int child_is_server(pid_t pid, const char *expected_path) {
    char executable[PROC_PIDPATHINFO_MAXSIZE];
    struct stat actual, expected;
    return proc_pidpath(pid, executable, sizeof(executable)) > 0 &&
        stat(executable, &actual) == 0 && stat(expected_path, &expected) == 0 &&
        actual.st_dev == expected.st_dev && actual.st_ino == expected.st_ino;
}

int wait_readable(int fd, int milliseconds) {
    struct pollfd descriptor = { .fd = fd, .events = POLLIN };
    return poll(&descriptor, 1, milliseconds);
}
