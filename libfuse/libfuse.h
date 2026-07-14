#ifndef C_LIBFUSE_H
#define C_LIBFUSE_H

#define FUSE_USE_VERSION 31
#define _FILE_OFFSET_BITS 64
#include <fuse.h>

int start_fuse(int argc, char** argv, struct fuse_operations* ops);
void fuse_file_info_set_flags(struct fuse_file_info* fi, int flags);
int fuse_file_info_get_flags(struct fuse_file_info* fi);


#endif
