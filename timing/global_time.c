#include <stdio.h>
#include <time.h>
#include <unistd.h>

int main() {
    struct timespec ts;
    // Pre-calculate the sleep duration: 100 microseconds (0.1ms)
    struct timespec delay = {0, 100000}; 

    while(1) {
        if (clock_gettime(CLOCK_REALTIME, &ts) == 0) {
            FILE *f = fopen("/dev/shm/global_clock.tmp", "w");
            if (f) {
                // %09ld ensures leading zeros for nanoseconds
                fprintf(f, "%ld.%09ld\n", ts.tv_sec, ts.tv_nsec);
                fclose(f);
                // Atomic rename prevents readers from seeing a partial file
                rename("/dev/shm/global_clock.tmp", "/dev/shm/global_clock");
            }
        }
        nanosleep(&delay, NULL);
    }
    return 0;
}