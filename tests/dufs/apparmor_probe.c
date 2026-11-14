/* Run without a mount sandbox to distinguish MAC denials from DAC/chroot. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/apparmor.h>
#include <sys/mman.h>
#include <unistd.h>

static int denied(const char *path, int flags) {
    errno = 0;
    int fd = open(path, flags);
    if (fd >= 0) close(fd);
    if (fd >= 0 || errno != EACCES) {
        fprintf(stderr, "Expected EACCES for %s, got fd=%d errno=%d\n", path, fd, errno);
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2 || access(argv[1], X_OK) != 0) return 1;
    const char *fixtures[] = { "/media/Films/allowed", "/tmp/dufs-forbidden" };
    for (unsigned int i = 0; i < sizeof(fixtures) / sizeof(fixtures[0]); i++) {
        int fd = open(fixtures[i], O_RDWR);
        if (fd < 0) { perror("unconfined read/write control"); return 1; }
        close(fd);
    }
    if (aa_change_profile("serve-dufs") != 0) {
        perror("enter serve-dufs");
        return 1;
    }
    int fd = open("/media/Films/allowed", O_RDONLY);
    if (fd < 0) { perror("allowed read"); return 1; }
    close(fd);
    if (denied("/media/Films/allowed", O_WRONLY) ||
        denied("/tmp/dufs-forbidden", O_RDONLY) ||
        denied("/tmp/dufs-forbidden", O_WRONLY)) return 1;
    fd = open(argv[1], O_RDONLY);
    if (fd < 0) { perror("store read control"); return 1; }
    void *mapping = mmap(NULL, 4096, PROT_READ, MAP_PRIVATE, fd, 0);
    if (mapping == MAP_FAILED) { perror("read mapping control"); return 1; }
    munmap(mapping, 4096);
    mapping = mmap(NULL, 4096, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
    if (mapping != MAP_FAILED || errno != EACCES) {
        fprintf(stderr, "Expected EACCES for unrelated executable mapping\n");
        return 1;
    }
    close(fd);
    execl(argv[1], argv[1], (char *)NULL);
    if (errno != EACCES) { perror("expected unrelated execution denial"); return 1; }
    return 0;
}
