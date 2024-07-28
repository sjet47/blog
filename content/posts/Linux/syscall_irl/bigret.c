typedef unsigned long long u64;

struct big {
    u64 a, b, c;
};

struct big ret_big(u64 a, u64 b, u64 c) {
    return (struct big){a, b, c};
}

int main(void) {
    struct big big = ret_big(1, 2, 3);
    return 0;
}
