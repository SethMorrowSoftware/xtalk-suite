/* orphan_channel_test.cpp — cb_data_channel's two orphan exits, DRIVEN.
 *
 * C++ gotcha 7 (datachannelxt/CLAUDE.md): a remote-initiated channel is BORN
 * inside cb_data_channel, so an early return there abandons a live
 * libdatachannel object with an open SCTP stream. Two such returns leaked one
 * until 2026-09-09 (23a2914): the peer already freed, and the handle table
 * full. Both now hand the rtc id to orphan_channel, and reap_orphan_channels
 * deletes it on the script thread (a callback may not rtcDelete*). That fix
 * was compile-verified only: the smoke test never reaches either exit, because
 * no public call can. "Peer already freed" is a race between an rtc thread and
 * dcx_peer_free; "table full" needs 65536 live channels.
 *
 * So this test links `datachannelxt_seams`, the SAME shim built with
 * DCX_TEST_SEAMS, never the shipped library (whose exports and ABI the seams
 * therefore cannot touch). Each seam makes one real condition true at the
 * point the production code tests it (datachannel_shim.cpp, g_seamForgetPeer
 * and g_seamRefuseInbound); everything else - the loopback, the SCTP stream, the
 * callback thread, orphan_channel, the reap inside dcx_poll - is the real code
 * path. Per exit, over a live in-process loopback:
 *
 *   1. A opens a channel on the established association; B's callback takes
 *      the exit. We watch WITHOUT polling (a poll would reap before we look):
 *      exactly one rtc id parked, still alive in libdatachannel (the callback
 *      did not delete it - rule 5), and no handle born for it on B.
 *   2. ONE dcx_poll reaps it: nothing parked, and libdatachannel no longer
 *      knows the id (its ids are never reused, so gone means deleted).
 *   3. The far end SEES the delete: A's channel gets E_CHANNEL_CLOSED. Before
 *      the fix B's end lived on and A's channel stayed open, so this is the
 *      user-visible half of the leak, observed through the public ABI.
 *   4. No E_CHANNEL_INCOMING ever names the orphan, and a fresh channel then
 *      opens both ways: the exit harmed nothing but the channel it refused.
 *
 * Plus the third reap path: an orphan still parked at dcx_cleanup is swept by
 * it rather than left for rtcCleanup.
 *
 * Same dialect as the smoke test (CHECK-counted, exit 1 on any failure), and
 * the same lanes: ctest runs it under ASan+UBSan and TSan, which judge the
 * seam state (guarded by g_mu) along with everything else. */

#include "../src/datachannel_shim.h"   /* dcx_* + dcx::test hooks + the seams */
#include "../src/dcx_record.h"

#ifndef DCX_TEST_SEAMS
#error "orphan_channel_test must link datachannelxt_seams (DCX_TEST_SEAMS)"
#endif

#include <chrono>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

static int g_fail = 0;
static int g_checks = 0;
#define CHECK(cond)                                                            \
    do {                                                                       \
        ++g_checks;                                                            \
        if (!(cond)) {                                                         \
            std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);        \
            ++g_fail;                                                          \
        }                                                                      \
    } while (0)

/* The drain, decoded under the frozen framing (the smoke test's walker,
 * trimmed to the fields this test reads). */
struct Ev {
    uint16_t type = 0;
    long long peer = 0;
    long long channel = 0;
    std::string sdp, sdpType, cand, mid, label;
};

static std::vector<Ev> drain_events() {
    std::vector<Ev> out;
    static std::vector<uint8_t> buf(65536);
    int n = dcx_poll(buf.data(), static_cast<int>(buf.size()));
    if (n < 0) {
        buf.resize(static_cast<size_t>(-n));
        n = dcx_poll(buf.data(), static_cast<int>(buf.size()));
    }
    CHECK(n >= 0);
    if (n <= 0) return out;
    dcx::RecordReader rd(buf.data(), buf.size());
    uint16_t count = dcx::RecordReader::rd_u16(rd.cursor());
    rd.skip(2);
    CHECK(count == static_cast<uint16_t>(n));
    for (uint16_t i = 0; i < count; ++i) {
        uint16_t type = dcx::RecordReader::rd_u16(rd.cursor());
        rd.skip(4);
        std::vector<dcx::Field> fields;
        CHECK(rd.read_record(fields));
        Ev ev;
        ev.type = type;
        for (const dcx::Field &f : fields) {
            switch (f.id) {
                case dcx::F_DC_PEER:      ev.peer = f.as_int(); break;
                case dcx::F_DC_CHANNEL:   ev.channel = f.as_int(); break;
                case dcx::F_DC_SDP:       ev.sdp = f.text(); break;
                case dcx::F_DC_SDP_TYPE:  ev.sdpType = f.text(); break;
                case dcx::F_DC_CANDIDATE: ev.cand = f.text(); break;
                case dcx::F_DC_MID:       ev.mid = f.text(); break;
                case dcx::F_DC_LABEL:     ev.label = f.text(); break;
                default: break;
            }
        }
        out.push_back(std::move(ev));
    }
    return out;
}

/* Everything the test must see across the whole run, so a stray event in ANY
 * pump is caught: every label B was ever told about. */
static std::vector<std::string> g_incomingOnB;

struct Loop {
    int pa = 0, pb = 0;
    /* Poll, shuttle signaling A <-> B, record B's INCOMING labels, offer each
     * event to `sink`, until `pred` holds or the deadline passes. */
    template <typename Pred, typename Sink>
    bool pump(Pred pred, Sink sink, int timeoutMs = 20000) const {
        auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::milliseconds(timeoutMs);
        for (;;) {
            for (const Ev &e : drain_events()) {
                int dst = (e.peer == pa) ? pb : pa;
                if (e.type == dcx::E_LOCAL_DESCRIPTION)
                    CHECK(dcx_set_remote_description(dst, e.sdp.c_str(), e.sdpType.c_str()) == DCX_OK);
                else if (e.type == dcx::E_LOCAL_CANDIDATE)
                    CHECK(dcx_add_remote_candidate(dst, e.cand.c_str(), e.mid.c_str()) == DCX_OK);
                if (e.type == dcx::E_CHANNEL_INCOMING && e.peer == pb)
                    g_incomingOnB.push_back(e.label);
                sink(e);
            }
            if (pred()) return true;
            if (std::chrono::steady_clock::now() > deadline) return false;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }

    /* A opens `label`; wait until both ends are open. Returns A's handle and
     * sets `bSide` to B's, or 0 on failure. */
    int open_pair(const char *label, int &bSide) const {
        int ca = dcx_channel_new(pa, label);
        CHECK(ca > 0);
        int cb = 0;
        bool aOpen = false, bOpen = false;
        const std::string want(label);
        bool ok = pump([&] { return aOpen && bOpen && cb != 0; },
            [&](const Ev &e) {
                if (e.type == dcx::E_CHANNEL_INCOMING && e.peer == pb && e.label == want)
                    cb = static_cast<int>(e.channel);
                if (e.type == dcx::E_CHANNEL_OPEN) {
                    if (e.channel == ca) aOpen = true;
                    if (cb != 0 && e.channel == cb) bOpen = true;
                }
            });
        CHECK(ok);
        bSide = cb;
        return ok ? ca : 0;
    }
};

/* Wait, WITHOUT polling, for the callback thread to park an orphan. */
static bool wait_for_parked(int want, int timeoutMs = 15000) {
    auto deadline = std::chrono::steady_clock::now() +
                    std::chrono::milliseconds(timeoutMs);
    while (dcx::test::seam_orphans_pending() < want) {
        if (std::chrono::steady_clock::now() > deadline) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    return true;
}

static bool saw_incoming(const char *label) {
    for (const std::string &l : g_incomingOnB)
        if (l == label) return true;
    return false;
}

/* One exit, steps 1-4 of the header. `arm` switches the seam on; `disarm`
 * restores it before the pumps that must run normally. */
template <typename Arm, typename Disarm>
static void drive_exit(const Loop &lp, const char *label, const char *after,
                       Arm arm, Disarm disarm) {
    std::printf("  exit: %s\n", label);
    const int liveBefore = dcx::test::live_channel_count();
    CHECK(dcx::test::seam_orphans_pending() == 0);
    arm();

    /* 1. A opens on the live association (in-band open, no new signaling);
     *    B's rtc thread runs cb_data_channel and takes the exit. */
    const int oa = dcx_channel_new(lp.pa, label);
    CHECK(oa > 0);
    if (oa <= 0) {
        char err[512] = {0};
        dcx_last_error(err, static_cast<int>(sizeof err) - 1);
        std::printf("  dcx_channel_new refused: live %d (before %d), last error: %s\n",
                    dcx::test::live_channel_count(), liveBefore, err);
    }
    const bool parked = wait_for_parked(1);
    CHECK(parked);
    CHECK(dcx::test::seam_orphans_pending() == 1);
    const int rtcId = dcx::test::seam_pending_orphan(0);
    CHECK(rtcId > 0);
    CHECK(dcx::test::seam_rtc_channel_alive(rtcId) == 1);     /* parked, not deleted */
    CHECK(dcx::test::live_channel_count() == liveBefore + 1); /* A's only: B got none */
    disarm();

    /* 2. The next dcx_poll reaps it on this (the script) thread. */
    drain_events();
    CHECK(dcx::test::seam_orphans_pending() == 0);
    CHECK(dcx::test::seam_rtc_channel_alive(rtcId) == 0);

    /* 3. The far end sees B's end deleted. */
    bool closed = false;
    bool ok = lp.pump([&] { return closed; }, [&](const Ev &e) {
        if (e.type == dcx::E_CHANNEL_CLOSED && e.channel == oa) closed = true;
    });
    CHECK(ok);
    CHECK(closed);
    CHECK(dcx_channel_is_open(oa) == 0);
    dcx_channel_free(oa);
    CHECK(dcx::test::live_channel_count() == liveBefore);

    /* 4. Nothing ever announced the orphan to B, and the association still
     *    opens a fresh channel both ways. */
    CHECK(!saw_incoming(label));
    int nb = 0;
    int na = lp.open_pair(after, nb);
    CHECK(na > 0 && nb > 0);
    CHECK(saw_incoming(after));
    dcx_channel_free(na);
    dcx_channel_free(nb);
    CHECK(dcx::test::live_channel_count() == liveBefore);
    CHECK(dcx::test::seam_orphans_pending() == 0);
}

int main() {
    std::printf("orphan_channel_test: cb_data_channel's two orphan exits over a "
                "live loopback (test-seam library)\n");
    CHECK(dcx_init() == DCX_OK);

    Loop lp;
    lp.pa = dcx_peer_new("");
    lp.pb = dcx_peer_new("");
    CHECK(lp.pa > 0 && lp.pb > 0);

    /* The association: one ordinary channel pair, opened through the real
     * signaling shuttle. Kept open so the SCTP transport stays up. */
    int baseB = 0;
    const int baseA = lp.open_pair("base", baseB);
    CHECK(baseA > 0 && baseB > 0);
    if (baseA <= 0 || baseB <= 0) {
        std::printf("  loopback never opened; nothing below can run\n");
        dcx_cleanup();
        std::printf("%d checks, %d failures\n", g_checks, g_fail);
        return 1;
    }
    CHECK(dcx::test::live_channel_count() == 2);

    /* Exit 1: the peer already freed (the lookup misses). */
    drive_exit(lp, "orphan-freed-peer", "after-freed-peer",
               [] { dcx::test::seam_forget_next_peer(1); },
               [] { dcx::test::seam_forget_next_peer(0); });

    /* Exit 2: the handle table full, for B's inbound registration only. (A
     * cap on the whole table raced: B's inbound twin can register before
     * dcx_channel_new registers A's own - see g_seamRefuseInbound.) */
    drive_exit(lp, "orphan-table-full", "after-table-full",
               [] { dcx::test::seam_refuse_next_inbound(1); },
               [] { dcx::test::seam_refuse_next_inbound(0); });

    /* The cleanup sweep: park one more, and let dcx_cleanup (not a poll) take
     * it. After rtcCleanup nothing is alive anyway, so the check that means
     * something is that OUR list was emptied by cleanup's own sweep. */
    dcx::test::seam_forget_next_peer(1);
    const int oc = dcx_channel_new(lp.pa, "orphan-at-cleanup");
    CHECK(oc > 0);
    CHECK(wait_for_parked(1));
    CHECK(dcx_cleanup() == DCX_OK);
    CHECK(dcx::test::seam_orphans_pending() == 0);
    CHECK(dcx::test::live_peer_count() == 0);
    CHECK(dcx::test::live_channel_count() == 0);
    CHECK(!saw_incoming("orphan-at-cleanup"));
    dcx::test::seam_forget_next_peer(0);

    std::printf("%d checks, %d failures\n", g_checks, g_fail);
    return g_fail == 0 ? 0 : 1;
}
