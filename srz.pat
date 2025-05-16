struct srz_header {
    u32 ori_size;
    u32 dsk_size;
    u32 bwt_index;
    u16 tree_size;
    char sent_byte;
    char esc_byte;
    char tree[tree_size];
    char data[dsk_size];
    u32 hash;
};

srz_header hdr @ 0x0;