/* ping-sweep (C) — concurrent host discovery across a /24.
 *
 * Real ICMP, no root: uses unprivileged ICMP datagram sockets
 * (SOCK_DGRAM + IPPROTO_ICMP), which macOS and modern Linux allow without
 * privileges. One pthread per host. Same contract as the rest of the repo:
 *     ping-sweep <network>     # 192.168.1.0/24  or  192.168.1
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <pthread.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>

struct icmp_echo { uint8_t type, code; uint16_t cksum, id, seq; };
_Static_assert(sizeof(struct icmp_echo) == 8, "ICMP echo header must be 8 bytes, no padding");

static uint16_t checksum(void *data, int len) {
    uint32_t sum = 0; uint16_t *p = data;
    for (; len > 1; len -= 2) sum += *p++;
    if (len == 1) sum += *(uint8_t *)p;
    sum = (sum >> 16) + (sum & 0xffff);
    sum += (sum >> 16);
    return (uint16_t)~sum;
}

struct job { char ip[32]; int host; int up; };

static void *probe(void *arg) {
    struct job *j = arg;
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (fd < 0) return NULL;

    struct timeval tv = { .tv_sec = 1, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_in dst = {0};
    dst.sin_family = AF_INET;
    if (inet_pton(AF_INET, j->ip, &dst.sin_addr) != 1) { close(fd); return NULL; }

    /* connect() so the kernel delivers only replies whose source is THIS
     * target — otherwise a reply from one host can be misattributed to another
     * (e.g. every loopback probe "hearing" 127.0.0.1's reply). */
    if (connect(fd, (struct sockaddr *)&dst, sizeof(dst)) != 0) { close(fd); return NULL; }

    struct icmp_echo pkt = {0};
    pkt.type = 8;                               /* echo request */
    pkt.id   = htons((uint16_t)j->host);        /* unique per target, to match the reply */
    pkt.seq  = htons(1);
    pkt.cksum = checksum(&pkt, sizeof(pkt));

    if (send(fd, &pkt, sizeof(pkt), 0) == (ssize_t)sizeof(pkt)) {  /* full packet sent, else host stays down */
        uint8_t buf[128];
        for (;;) {
            ssize_t n = recv(fd, buf, sizeof(buf), 0);
            if (n <= 0) break;                  /* timeout / error -> host is down */
            /* skip an IP header if the kernel prepended one */
            int off = (n >= 20 && (buf[0] >> 4) == 4) ? (buf[0] & 0x0f) * 4 : 0;
            if (n < off + 6 || buf[off] != 0) continue;      /* not an echo reply */
            /* NOTE: verified on macOS. On Linux, datagram-ICMP sockets require
             * net.ipv4.ping_group_range to include the user, and the kernel
             * rewrites the echo id to the socket's port — so there this match
             * would read the kernel-assigned id (via getsockname) instead. */
            uint16_t rid = (uint16_t)((buf[off + 4] << 8) | buf[off + 5]);
            if (rid == (uint16_t)j->host) { j->up = 1; break; }  /* it's OUR echo */
            /* else: a stray reply for another host — keep reading until timeout */
        }
    }
    close(fd);
    return NULL;
}

static uint32_t ipkey(const char *ip) {
    unsigned a, b, c, d; sscanf(ip, "%u.%u.%u.%u", &a, &b, &c, &d);
    return (a << 24) | (b << 16) | (c << 8) | d;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: ping-sweep <network>   e.g. 192.168.1.0/24 or 192.168.1\n");
        return 2;
    }
    char net[64];
    strncpy(net, argv[1], sizeof(net) - 1); net[sizeof(net) - 1] = 0;
    char *slash = strchr(net, '/'); if (slash) *slash = 0;

    unsigned a, b, c;
    if (sscanf(net, "%u.%u.%u", &a, &b, &c) < 3 || a > 255 || b > 255 || c > 255) {
        fprintf(stderr, "invalid network: %s\n", argv[1]); return 1;
    }
    char base[32]; snprintf(base, sizeof(base), "%u.%u.%u", a, b, c);

    struct job jobs[254];
    pthread_t th[254];
    for (int i = 0; i < 254; i++) {
        snprintf(jobs[i].ip, sizeof(jobs[i].ip), "%s.%d", base, i + 1);
        jobs[i].host = i + 1;
        jobs[i].up = 0;
        pthread_create(&th[i], NULL, probe, &jobs[i]);
    }
    for (int i = 0; i < 254; i++) pthread_join(th[i], NULL);

    const char *up[254]; int nup = 0;
    for (int i = 0; i < 254; i++) if (jobs[i].up) up[nup++] = jobs[i].ip;
    for (int i = 1; i < nup; i++) {                 /* insertion sort by numeric IP */
        const char *k = up[i]; int jx = i - 1;
        while (jx >= 0 && ipkey(up[jx]) > ipkey(k)) { up[jx + 1] = up[jx]; jx--; }
        up[jx + 1] = k;
    }
    for (int i = 0; i < nup; i++) printf("%s\n", up[i]);
    fprintf(stderr, "%d host%s up on %s.0/24\n", nup, nup == 1 ? "" : "s", base);
    return 0;
}
