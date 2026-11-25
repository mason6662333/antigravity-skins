#include <sys/types.h>
pid_t start_skin_host(const char *binary, int *send_fd, int *receive_fd);
int child_is_server(pid_t pid, const char *expected_path);
int wait_readable(int fd, int milliseconds);
