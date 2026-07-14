#include "libfuse.h"

int start_fuse(int argc, char** argv, struct fuse_operations* ops) {
    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);

    int ret = fuse_main(args.argc, args.argv, ops, NULL);
    fuse_opt_free_args(&args);

    return ret;
}

void fuse_file_info_set_flags(struct fuse_file_info* fi, int flags) {
    fi->flags = flags;
}

int fuse_file_info_get_flags(struct fuse_file_info* fi) {
    return fi->flags;
}
